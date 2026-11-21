import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telephony/telephony.dart';
import 'package:uuid/uuid.dart';

import '../supabase_client.dart';
import '../utils/app_logger.dart';
import 'sim_service.dart';
import 'ussd_engine.dart';

@pragma('vm:entry-point')
Future<void> handleBackgroundSms(SmsMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  await GatewaySupabase.initialize();
  await SmsReceiverService().handleMessage(
    message.address ?? '',
    message.body ?? '',
  );
}

class SmsReceiverService {
  static bool _isListening = false;

  final Telephony _telephony = Telephony.instance;
  final UssdEngine _engine = UssdEngine();
  final _uuid = const Uuid();

  Future<void> start() async {
    if (_isListening) return;
    _telephony.listenIncomingSms(
      onNewMessage: (SmsMessage message) {
        unawaited(handleMessage(message.address ?? '', message.body ?? ''));
      },
      onBackgroundMessage: handleBackgroundSms,
      listenInBackground: true,
    );
    _isListening = true;
    AppLogger.instance.success('AgriMarket SMS receiver listening');
  }

  String normalizePhone(String phone) {
    final digits = phone.replaceAll(RegExp(r'[^\d+]'), '');
    if (digits.startsWith('+')) return digits;
    if (digits.startsWith('00')) return '+${digits.substring(2)}';
    if (digits.startsWith('0')) return '+256${digits.substring(1)}';
    return '+256$digits';
  }

  Future<int?> _receivingSubscriptionId() async {
    final preferences = await SharedPreferences.getInstance();
    final saved = preferences.getInt('sim_subscription_id');
    if (saved != null) return saved;
    final slots = await SimService().getSimSlots();
    return slots.isEmpty ? null : slots.first.subscriptionId;
  }

  Future<void> handleMessage(String sender, String body) async {
    final normalizedSender = normalizePhone(sender);
    final sessionId = _uuid.v4();
    int? subscriptionId;

    try {
      subscriptionId = await _receivingSubscriptionId();
    } catch (error) {
      AppLogger.instance.error('Could not read SMS subscription: $error');
    }

    try {
      await GatewaySupabase.client.from('incoming_sms').insert({
        'sender': normalizedSender,
        'body': body,
        'subscription_id': subscriptionId,
        'session_id': sessionId,
      });
    } catch (error) {
      AppLogger.instance.error('Could not log inbound SMS: $error');
    }

    AppLogger.instance.info(
      'Inbound SMS from $normalizedSender: ${body.length > 60 ? '${body.substring(0, 60)}...' : body}',
    );

    final isTrigger = body.trim().toUpperCase() == 'SGW';
    String? reply;
    if (!isTrigger) {
      try {
        if (!await _engine.hasActiveSession(normalizedSender)) {
          AppLogger.instance.info(
            'SMS ignored; sender has no AgriMarket session',
          );
          return;
        }
      } catch (error) {
        AppLogger.instance.error('Could not check AgriMarket session: $error');
        return;
      }
    }

    try {
      reply = await _engine.process(normalizedSender, body);
    } catch (error) {
      AppLogger.instance.error('Could not process marketplace SMS: $error');
      reply = 'Sorry, we could not process your request. Please try again.';
    }

    if (reply == null) return;

    var status = 'sent';
    String? sendError;
    try {
      await _telephony.sendSms(
        to: normalizedSender,
        message: reply,
        isMultipart: reply.length > 160,
      );
      AppLogger.instance.success('Instant AgriMarket reply sent');
    } catch (error) {
      status = 'pending';
      sendError = error.toString();
      AppLogger.instance.error('Instant SMS send failed: $error');
    }

    try {
      await GatewaySupabase.client.from('outbound_sms').insert({
        'phone': normalizedSender,
        'message': reply,
        'status': status,
        'attempts': 0,
        'last_error': sendError,
        'session_id': sessionId,
        'reply_to_subscription_id': subscriptionId,
      });
    } catch (error) {
      AppLogger.instance.error('Could not log outbound SMS: $error');
    }
  }
}
