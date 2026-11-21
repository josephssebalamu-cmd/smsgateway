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
  String _activeSim = 'No SIM selected';

  @override
  void initState() {
    super.initState();
    _loadActiveSim();
    _receiver.start();
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
      appBar: AppBar(title: const Text('Gateway')),
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
    _receiver.stop();
    super.dispose();
  }
}
