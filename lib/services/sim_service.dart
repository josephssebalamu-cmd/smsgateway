import 'package:flutter/services.dart';

class SimSlot {
  final int subscriptionId;
  final int slotIndex;
  final String displayName;
  final String phoneNumber;

  const SimSlot({
    required this.subscriptionId,
    required this.slotIndex,
    required this.displayName,
    required this.phoneNumber,
  });

  factory SimSlot.fromMap(Map<Object?, Object?> map) {
    return SimSlot(
      subscriptionId: map['subscriptionId'] as int? ?? -1,
      slotIndex: map['slotIndex'] as int? ?? 0,
      displayName: map['displayName'] as String? ?? 'SIM',
      phoneNumber: map['phoneNumber'] as String? ?? '',
    );
  }
}

class SimService {
  static const MethodChannel _channel = MethodChannel(
    'com.fasbec.gateway/android',
  );

  Future<List<SimSlot>> getSimSlots() async {
    final result = await _channel.invokeListMethod<Object?>('getSimSlots');
    return (result ?? const <Object?>[])
        .whereType<Map>()
        .map((map) => SimSlot.fromMap(Map<Object?, Object?>.from(map)))
        .toList();
  }

  Future<void> sendSms({
    required String phone,
    required String message,
    required int? subscriptionId,
  }) async {
    await _channel.invokeMethod<bool>('sendSms', {
      'phone': phone,
      'message': message,
      'subscriptionId': subscriptionId,
    });
  }
}
