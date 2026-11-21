import 'dart:async';

import 'package:flutter_background/flutter_background.dart';
import 'package:telephony/telephony.dart';

import '../supabase_client.dart';
import '../utils/app_logger.dart';

class PollingService {
  static final Set<String> _currentlySending = {};
  Timer? _timer;
  Duration _delay = const Duration(seconds: 15);
  bool _isFetching = false;
  DateTime? lastPollTime;
  bool isPolling = false;
  final Telephony _telephony = Telephony.instance;

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
    if (!isPolling || _isFetching) return;
    _isFetching = true;
    lastPollTime = DateTime.now();
    try {
      final rows = await GatewaySupabase.client.rpc(
        'claim_outbound_sms',
        params: {'batch_size': 5},
      );

      for (final row in (rows as List).cast<Map<String, dynamic>>()) {
        final id = row['id'].toString();
        if (_currentlySending.contains(id)) continue;
        _currentlySending.add(id);
        final attempts = (row['attempts'] as num?)?.toInt() ?? 1;

        try {
          await _telephony.sendSms(
            to: row['phone'] as String,
            message: row['message'] as String,
            isMultipart: (row['message'] as String).length > 160,
          );
          await _onSendStatus(row, sent: true, attempts: attempts, error: null);
          AppLogger.instance.success('Queued SMS sent: $id');
        } catch (error) {
          await _onSendStatus(
            row,
            sent: false,
            attempts: attempts,
            error: error.toString(),
          );
          AppLogger.instance.error('Queued SMS failed: $error');
        } finally {
          _currentlySending.remove(id);
        }
      }
      _delay = const Duration(seconds: 15);
    } catch (error) {
      AppLogger.instance.error('Outbound poll failed: $error');
      _delay = Duration(
        seconds: _delay.inSeconds < 240
            ? (_delay.inSeconds * 2).clamp(30, 240)
            : 240,
      );
      _schedule();
    } finally {
      _isFetching = false;
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
