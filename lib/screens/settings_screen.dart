import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:receive_sms/receive_sms.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/sim_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _gatewayPhoneController = TextEditingController();
  final _simService = SimService();
  final _receiveSms = ReceiveSms();
  List<SimSlot> _slots = [];
  SimSlot? _selected;
  bool _smsPermission = false;
  bool _phonePermission = false;
  bool _notificationPermission = false;
  bool _batteryExempt = false;
  bool _defaultSmsHandler = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final preferences = await SharedPreferences.getInstance();
    _gatewayPhoneController.text =
        preferences.getString('gateway_phone') ?? '+256773896818';
    _slots = await _simService.getSimSlots();
    final selectedId = preferences.getInt('sim_subscription_id');
    _selected = _slots.cast<SimSlot?>().firstWhere(
      (slot) => slot?.subscriptionId == selectedId,
      orElse: () => _slots.isEmpty ? null : _slots.first,
    );
    await _refreshPermissions();
  }

  Future<void> _refreshPermissions() async {
    final sms = await Permission.sms.status;
    final phone = await Permission.phone.status;
    final notification = await Permission.notification.status;
    final battery = await Permission.ignoreBatteryOptimizations.status;
    final defaultHandler = await _receiveSms.isDefaultSmsApp;
    if (!mounted) return;
    setState(() {
      _smsPermission = sms.isGranted;
      _phonePermission = phone.isGranted;
      _notificationPermission = notification.isGranted;
      _batteryExempt = battery.isGranted;
      _defaultSmsHandler = defaultHandler;
    });
  }

  Future<void> _saveGatewayPhone() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      'gateway_phone',
      _gatewayPhoneController.text.trim(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<SimSlot>(
            initialValue: _selected,
            decoration: const InputDecoration(labelText: 'Active SIM'),
            items: _slots.map((slot) {
              return DropdownMenuItem(
                value: slot,
                child: Text(slot.displayName),
              );
            }).toList(),
            onChanged: (slot) async {
              if (slot == null) return;
              final preferences = await SharedPreferences.getInstance();
              await preferences.setInt(
                'sim_subscription_id',
                slot.subscriptionId,
              );
              await preferences.setString('sim_display_name', slot.displayName);
              setState(() => _selected = slot);
            },
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _gatewayPhoneController,
            decoration: const InputDecoration(
              labelText: 'Gateway phone',
              hintText: '+256700000000',
            ),
            keyboardType: TextInputType.phone,
            onChanged: (_) => _saveGatewayPhone(),
          ),
          const SizedBox(height: 24),
          Text('Permissions', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _PermissionTile(
            title: 'SMS',
            granted: _smsPermission,
            onRequest: () async {
              await _receiveSms.requestPermission();
              await _refreshPermissions();
            },
          ),
          _PermissionTile(
            title: 'Phone state',
            granted: _phonePermission,
            onRequest: () async {
              await Permission.phone.request();
              await _refreshPermissions();
            },
          ),
          _PermissionTile(
            title: 'Notifications',
            granted: _notificationPermission,
            onRequest: () async {
              await Permission.notification.request();
              await _refreshPermissions();
            },
          ),
          _PermissionTile(
            title: 'Battery optimization exemption',
            granted: _batteryExempt,
            onRequest: () async {
              await Permission.ignoreBatteryOptimizations.request();
              await _refreshPermissions();
            },
          ),
          _PermissionTile(
            title: 'Default SMS handler',
            granted: _defaultSmsHandler,
            onRequest: () async {
              await _receiveSms.requestDefaultSmsApp();
              await _refreshPermissions();
            },
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _gatewayPhoneController.dispose();
    super.dispose();
  }
}

class _PermissionTile extends StatelessWidget {
  final String title;
  final bool granted;
  final Future<void> Function() onRequest;

  const _PermissionTile({
    required this.title,
    required this.granted,
    required this.onRequest,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      trailing: Text(granted ? 'Granted' : 'Missing'),
      onTap: granted ? null : onRequest,
    );
  }
}
