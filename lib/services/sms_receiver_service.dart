import 'dart:async';

import 'package:receive_sms/receive_sms.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../supabase_client.dart';
import '../utils/command_parser.dart';
import 'sim_service.dart';

class SmsReceiverService {
  StreamSubscription? _subscription;
  final _receiveSms = ReceiveSms();
  bool _handling = false;

  Future<void> start() async {
    if (_subscription != null) return;
    _subscription = _receiveSms.incomingSmsStream.listen((message) {
      if (_handling) return;
      _handling = true;
      _handleMessage(message.address, message.body).whenComplete(() {
        _handling = false;
      });
    });
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
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

  Future<void> _handleMessage(String sender, String body) async {
    final normalizedSender = normalizePhone(sender);
    final subscriptionId = await _receivingSubscriptionId();

    await GatewaySupabase.client.from('incoming_sms').insert({
      'sender': normalizedSender,
      'body': body,
      'subscription_id': subscriptionId,
    });

    final parsed = CommandParser.parse(body);
    String reply;

    if (parsed is CommandError) {
      reply = parsed.text;
    } else if (parsed is ParsedCommand) {
      try {
        switch (parsed.verb) {
          case 'ADD':
            final inserted = await GatewaySupabase.client
                .from('products')
                .insert({
                  'name': parsed.argument,
                  'price': double.parse(parsed.price!),
                  'quantity': parsed.quantity,
                  'created_by': normalizedSender,
                })
                .select('id')
                .single();
            final id = inserted['id'].toString();
            reply = 'OK #${id.replaceAll('-', '').substring(0, 6)} added';
            break;
          case 'SEARCH':
            final rows = await GatewaySupabase.client.rpc(
              'search_products',
              params: {'q': parsed.argument},
            );
            final products = (rows as List).cast<Map<String, dynamic>>();
            if (products.isEmpty) {
              reply = 'No products found.';
            } else {
              reply = products
                  .map((product) {
                    final id = product['id'].toString();
                    final shortId = id.replaceAll('-', '').substring(0, 6);
                    return '#$shortId ${product['name']} | ${product['price']} | qty ${product['quantity']}';
                  })
                  .join('\n');
            }
            break;
          case 'LIST':
            final rows = await GatewaySupabase.client
                .from('products')
                .select('id,name,price,quantity')
                .order('created_at', ascending: false)
                .limit(5);
            final products = rows.cast<Map<String, dynamic>>();
            if (products.isEmpty) {
              reply = 'No products.';
            } else {
              reply = products
                  .map((product) {
                    final id = product['id'].toString();
                    final shortId = id.replaceAll('-', '').substring(0, 6);
                    return '#$shortId ${product['name']} | ${product['price']} | qty ${product['quantity']}';
                  })
                  .join('\n');
            }
            break;
          case 'DELETE':
            final prefix = parsed.argument.replaceAll('-', '').toLowerCase();
            final rows = await GatewaySupabase.client
                .from('products')
                .select('id,name');
            final matches = rows.cast<Map<String, dynamic>>().where((product) {
              final id = product['id']
                  .toString()
                  .replaceAll('-', '')
                  .toLowerCase();
              return id.startsWith(prefix);
            }).toList();
            if (matches.isEmpty) {
              reply = 'ERR Product not found.';
            } else if (matches.length != 1) {
              reply = 'ERR Product prefix is ambiguous.';
            } else {
              await GatewaySupabase.client
                  .from('products')
                  .delete()
                  .eq('id', matches.first['id']);
              reply =
                  'OK #${prefix.substring(0, prefix.length < 6 ? prefix.length : 6)} deleted';
            }
            break;
          case 'HELP':
            reply =
                'ADD name | price | qty\nSEARCH query\nLIST\nDELETE uuid-prefix\nHELP';
            break;
          default:
            reply = 'ERR Unknown command.';
        }
      } catch (_) {
        reply = 'ERR Could not execute command.';
      }
    } else {
      reply = 'ERR Unknown command.';
    }

    await GatewaySupabase.client.from('outbound_sms').insert({
      'phone': normalizedSender,
      'message': reply,
      'status': 'pending',
      'attempts': 0,
      'reply_to_subscription_id': subscriptionId,
      'kind': 'command_reply',
    });
  }
}
