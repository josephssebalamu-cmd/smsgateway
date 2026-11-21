import 'dart:async';

import 'package:flutter_background/flutter_background.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../supabase_client.dart';
import 'sim_service.dart';

class PollingService {
  Timer? _timer;
  Duration _delay = const Duration(seconds: 15);
  DateTime? lastPollTime;
  bool isPolling = false;
  final SimService _simService = SimService();

  Future<bool> start() async {
    if (isPolling) return true;
    final initialized = await FlutterBackground.initialize(
      androidConfig: const FlutterBackgroundAndroidConfig(
        notificationTitle: 'Fasbec SMS gateway',
        notificationText: 'SMS gateway is polling for outbound messages',
      ),
    );
    if (!initialized) return false;
    if (!await FlutterBackground.enableBackgroundExecution()) return false;
    isPolling = true;
    _delay = const Duration(seconds: 15);
    await poll();
    _schedule();
    return true;
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    isPolling = false;
    await FlutterBackground.disableBackgroundExecution();
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer.periodic(_delay, (_) => poll());
  }

  Future<void> poll() async {
    if (!isPolling) return;
    lastPollTime = DateTime.now();
    try {
      final rows = await GatewaySupabase.client.rpc(
        'claim_outbound_sms',
        params: {'batch_size': 5},
      );
      final preferences = await SharedPreferences.getInstance();
      final fallbackSubscriptionId = preferences.getInt('sim_subscription_id');

      for (final row in (rows as List).cast<Map<String, dynamic>>()) {
        final subscriptionId =
            row['reply_to_subscription_id'] as int? ?? fallbackSubscriptionId;
        final attempts = row['attempts'] as int? ?? 1;

        try {
          await _simService.sendSms(
            phone: row['phone'] as String,
            message: row['message'] as String,
            subscriptionId: subscriptionId,
          );
          await _onSendStatus(row, sent: true, attempts: attempts, error: null);
        } catch (error) {
          await _onSendStatus(
            row,
            sent: false,
            attempts: attempts,
            error: error.toString(),
          );
        }
      }
      _delay = const Duration(seconds: 15);
    } catch (_) {
      _delay = Duration(
        seconds: _delay.inSeconds < 240
            ? (_delay.inSeconds * 2).clamp(30, 240)
            : 240,
      );
      _schedule();
    }
  }

  Future<void> _onSendStatus(
    Map<String, dynamic> row, {
    required bool sent,
    required int attempts,
    required String? error,
  }) async {
    if (sent) {
      await GatewaySupabase.client
          .from('outbound_sms')
          .update({
            'status': 'sent',
            'sent_at': DateTime.now().toUtc().toIso8601String(),
            'last_error': null,
          })
          .eq('id', row['id']);
    } else if (attempts >= 3) {
      await GatewaySupabase.client
          .from('outbound_sms')
          .update({'status': 'failed', 'last_error': error})
          .eq('id', row['id']);
    } else {
      await GatewaySupabase.client
          .from('outbound_sms')
          .update({
            'status': 'pending',
            'claimed_at': null,
            'last_error': error,
          })
          .eq('id', row['id']);
    }
  }
}
