import '../core/models.dart';
import '../core/native.dart';
import 'chat_parser.dart';

/// Combines exported chats (full history, in + out) with live notification counts
/// (incoming only, from the moment notification access was granted).
///
/// For a chat that was also exported, notifications up to the last exported
/// message are dropped so nothing is counted twice.
List<MsgEvent> whatsAppEvents({
  required List<ParsedChat> chats,
  required List<WaNotification> notifications,
  required String myName,
}) {
  final me = myName.trim().toLowerCase();
  final events = <MsgEvent>[];
  final exportedUntil = <String, DateTime>{};
  for (final c in chats) {
    final key = c.name.toLowerCase();
    for (final m in c.messages) {
      events.add(MsgEvent(
        time: m.time,
        outgoing: me.isNotEmpty && m.sender.toLowerCase() == me,
        source: Source.whatsapp,
        contact: c.name,
        bytes: m.length,
      ));
      final cur = exportedUntil[key];
      if (cur == null || m.time.isAfter(cur)) exportedUntil[key] = m.time;
    }
  }
  for (final n in notifications) {
    final until = exportedUntil[n.chat.toLowerCase()];
    if (until != null && !n.time.isAfter(until)) continue;
    events.add(MsgEvent(time: n.time, outgoing: false, source: Source.whatsapp, contact: n.chat));
  }
  return events;
}
