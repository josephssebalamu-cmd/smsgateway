import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/polling_service.dart';
import '../services/sms_receiver_service.dart';

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
  bool _connected = true;

  @override
  void initState() {
    super.initState();
    _loadActiveSim();
    _receiver.start();
    _listenForConnectivity();
  }

  void _listenForConnectivity() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      results,
    ) async {
      final connected =
          results.isNotEmpty &&
          !results.every((r) => r == ConnectivityResult.none);
      if (!mounted) return;
      setState(() => _connected = connected);
      if (connected && !_polling.isPolling) {
        await _polling.start();
        if (mounted) setState(() {});
      } else if (!connected && _polling.isPolling) {
        await _polling.stop();
        if (mounted) setState(() {});
      }
    });
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
        title: const Text('Gateway'),
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
      body: ListView(
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
            label: Text(_polling.isPolling ? 'Stop polling' : 'Start polling'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _receiver.stop();
    super.dispose();
  }
}
