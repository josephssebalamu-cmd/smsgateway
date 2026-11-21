import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/polling_service.dart';
import '../services/sms_receiver_service.dart';
import '../supabase_client.dart';
import '../utils/app_logger.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final PollingService _polling = PollingService();
  final SmsReceiverService _receiver = SmsReceiverService();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  String _activeSim = 'No SIM selected';
  List<Map<String, dynamic>> _activeSessions = [];
  bool _connected = false;
  bool _loadingSessions = true;

  @override
  void initState() {
    super.initState();
    _loadActiveSim();
    _receiver.start().catchError((Object error) {
      AppLogger.instance.error('Could not start SMS receiver: $error');
    });
    _listenForConnectivity();
    _refreshSessions();
  }

  void _listenForConnectivity() {
    Connectivity().checkConnectivity().then(_updateConnectivity).catchError((
      Object error,
    ) {
      if (mounted) {
        setState(() => _connected = false);
      }
    });
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      results,
    ) {
      _updateConnectivity(results);
    });
  }

  Future<void> _updateConnectivity(List<ConnectivityResult> results) async {
    final connected =
        results.isNotEmpty &&
        !results.every((r) => r == ConnectivityResult.none);
    if (!mounted) return;
    setState(() => _connected = connected);
    try {
      if (connected && !_polling.isPolling) {
        final started = await _polling.start();
        if (!started) {
          AppLogger.instance.error('Background polling could not be started');
        }
      } else if (!connected && _polling.isPolling) {
        await _polling.stop();
      }
    } catch (error) {
      AppLogger.instance.error('Could not update background polling: $error');
    }
    if (mounted) setState(() {});
  }

  Future<void> _refreshSessions() async {
    setState(() => _loadingSessions = true);
    try {
      final rows = await GatewaySupabase.client
          .from('sessions')
          .select('phone,current_menu,updated_at')
          .order('updated_at', ascending: false)
          .limit(50);
      if (!mounted) return;
      setState(() {
        _activeSessions = rows.cast<Map<String, dynamic>>();
        _loadingSessions = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadingSessions = false);
      AppLogger.instance.error('Could not load active sessions: $error');
    }
  }

  Future<void> _loadActiveSim() async {
    final preferences = await SharedPreferences.getInstance();
    final name = preferences.getString('sim_display_name');
    if (mounted) {
      setState(() => _activeSim = name ?? 'No SIM selected');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AgriMarket Gateway'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Icon(
              Icons.wifi,
              color: _connected ? Colors.green : Colors.red,
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshSessions,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _polling.isPolling ? 'Polling active' : 'Polling stopped',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text('Active SIM: $_activeSim'),
                    Text(
                      'Last poll: ${_polling.lastPollTime?.toLocal().toString() ?? 'Never'}',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () async {
                if (_polling.isPolling) {
                  await _polling.stop();
                } else {
                  await _polling.start();
                }
                if (mounted) setState(() {});
              },
              icon: Icon(_polling.isPolling ? Icons.stop : Icons.play_arrow),
              label: Text(
                _polling.isPolling ? 'Stop polling' : 'Start polling',
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Active Sessions',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            if (_loadingSessions)
              const Center(child: CircularProgressIndicator())
            else if (_activeSessions.isEmpty)
              const Card(
                child: ListTile(
                  title: Text('No users are currently in a menu'),
                ),
              )
            else
              ..._activeSessions.map((session) {
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.person_outline),
                    title: Text(
                      session['phone']?.toString() ?? 'Unknown phone',
                    ),
                    subtitle: Text(
                      'Menu: ${session['current_menu'] ?? 'Unknown'}\n'
                      'Updated: ${session['updated_at'] ?? ''}',
                    ),
                    isThreeLine: true,
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    super.dispose();
  }
}
