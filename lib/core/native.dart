/// Bridge to the Android-only Kotlin code (SMS provider, WhatsApp notification listener).
library;

import 'dart:io';

import 'package:flutter/services.dart';

import 'models.dart';

class SmsRecord {
  final DateTime time;
  final bool outgoing;
  final String address;
  final String? name;
  final int bytes;
  final bool mms;

  const SmsRecord(this.time, this.outgoing, this.address, this.name, this.bytes, this.mms);

  MsgEvent toEvent() =>
      MsgEvent(time: time, outgoing: outgoing, source: Source.sms, contact: name ?? address, bytes: bytes);
}

class WaNotification {
  final DateTime time;
  final String chat;
  final String sender;
  const WaNotification(this.time, this.chat, this.sender);
}

/// Normalises Israeli numbers so "+972 50-123-4567" and "0501234567" are one contact.
String normalizePhone(String a) {
  var s = a.replaceAll(RegExp(r'[\s\-()]'), '');
  if (s.startsWith('+972')) s = '0${s.substring(4)}';
  if (s.startsWith('972') && s.length == 12) s = '0${s.substring(3)}';
  return s;
}

class NativeBridge {
  static const _ch = MethodChannel('message_hub/native');

  static bool get supported => Platform.isAndroid;

  static Future<List<SmsRecord>> readSms({DateTime? since}) async {
    if (!supported) return const [];
    final rows = await _ch.invokeListMethod<Map>('readSms', {
      'sinceMs': since?.millisecondsSinceEpoch ?? 0,
    });
    return [
      for (final r in rows ?? const <Map>[])
        SmsRecord(
          DateTime.fromMillisecondsSinceEpoch(r['date'] as int),
          r['out'] as bool,
          normalizePhone(r['address'] as String? ?? ''),
          r['name'] as String?,
          r['bytes'] as int,
          r['mms'] as bool,
        ),
    ];
  }

  static Future<bool> notificationAccessGranted() async =>
      supported && (await _ch.invokeMethod<bool>('notificationAccessGranted') ?? false);

  static Future<void> openNotificationAccessSettings() => _ch.invokeMethod('openNotificationAccessSettings');

  static Future<List<WaNotification>> whatsAppNotifications({DateTime? since}) async {
    if (!supported) return const [];
    final rows = await _ch.invokeListMethod<Map>('waNotifications', {
      'sinceMs': since?.millisecondsSinceEpoch ?? 0,
    });
    return [
      for (final r in rows ?? const <Map>[])
        WaNotification(DateTime.fromMillisecondsSinceEpoch(r['ts'] as int), r['chat'] as String,
            r['sender'] as String),
    ];
  }

  static Future<void> clearWhatsAppNotifications() => _ch.invokeMethod('clearWaNotifications');
}
