/// Parser for WhatsApp "Export chat" .txt files (Android and iPhone, Hebrew and English).
library;

class WaMessage {
  final DateTime time;
  final String sender;
  final bool isMedia;
  final int length;

  const WaMessage(this.time, this.sender, {this.isMedia = false, this.length = 0});
}

class ParsedChat {
  final String name;
  final List<WaMessage> messages;
  final int attachmentBytes;

  const ParsedChat(this.name, this.messages, {this.attachmentBytes = 0});

  Set<String> get senders => messages.map((m) => m.sender).toSet();
  bool get isGroup => senders.length > 2;
}

// Invisible direction marks and odd spaces that WhatsApp sprinkles into exports.
final _invisible = RegExp('[\u200e\u200f\u202a-\u202e\u2066-\u2069\ufeff]');
final _oddSpace = RegExp('[\u00a0\u202f]');

final _header = RegExp(
  r'^\[?(\d{1,4})[./-](\d{1,2})[./-](\d{1,4}),?\s+(\d{1,2}):(\d{2})(?::(\d{2}))?'
  r'\s*([AaPp]\.?\s?[Mm]\.?|לפנה"צ|אחה"צ|לפני הצהריים|אחר הצהריים)?\]?\s*(?:-\s*)?'
  r'([^:]{1,80}?):\s(.*)$',
);

final _media = RegExp(
  r'(<media omitted>|<המדיה לא נכללה>|<מדיה הושמטה>|\b(image|video|audio|sticker|gif|document) omitted|'
  r'(תמונה|סרטון|וידאו|הקלטה|שמע|מדבקה|מסמך|קובץ gif) (הושמט|הושמטה|לא נכלל)|'
  r'<attached: |\(file attached\)|\(קובץ מצורף\))',
  caseSensitive: false,
);

String _clean(String s) => s.replaceAll(_invisible, '').replaceAll(_oddSpace, ' ');

/// Extracts the chat partner / group name from an export file name.
String chatNameFromFile(String fileName) {
  var n = fileName.replaceAll(RegExp(r'\.(txt|zip)$', caseSensitive: false), '');
  for (final p in [
    RegExp(r'^WhatsApp Chat (with|-) ', caseSensitive: false),
    RegExp(r"^צ'?אט (WhatsApp|וואטסאפ) עם ", caseSensitive: false),
    RegExp(r'^WhatsApp ?'),
  ]) {
    n = n.replaceFirst(p, '');
  }
  n = n.replaceFirst(RegExp(r'\s*\(\d+\)$'), ''); // "(1)" duplicates
  return n.trim().isEmpty ? fileName : n.trim();
}

ParsedChat parseChat(String content, {required String chatName, int attachmentBytes = 0}) {
  final raw = <(_Fields, String)>[];
  var firstMax = 0, secondMax = 0;
  var firstIsYear = false;
  for (final line in content.split(RegExp(r'\r?\n'))) {
    final m = _header.firstMatch(_clean(line));
    if (m == null) continue; // continuation line, or a system message without "name:"
    final f = _Fields(m);
    if (f.a > 31) {
      firstIsYear = true;
    } else {
      if (f.a > firstMax) firstMax = f.a;
      if (f.b > secondMax) secondMax = f.b;
    }
    raw.add((f, m.group(9)!));
  }
  // Day-first unless the data proves otherwise (Israeli exports are day-first).
  final monthFirst = !firstIsYear && secondMax > 12 && firstMax <= 12;

  final msgs = <WaMessage>[];
  for (final (f, body) in raw) {
    final t = f.toDate(monthFirst: monthFirst, yearFirst: firstIsYear);
    if (t == null) continue;
    msgs.add(WaMessage(t, f.sender, isMedia: _media.hasMatch(body), length: body.length));
  }
  return ParsedChat(chatName, msgs, attachmentBytes: attachmentBytes);
}

/// Guesses "me": the sender who appears in the most chats (you are in all of them).
String? guessMyName(List<ParsedChat> chats) {
  if (chats.length < 2) return null;
  final counts = <String, int>{};
  for (final c in chats) {
    for (final s in c.senders) {
      counts.update(s, (v) => v + 1, ifAbsent: () => 1);
    }
  }
  final sorted = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  if (sorted.length > 1 && sorted[0].value == sorted[1].value) return null;
  return sorted.first.value >= 2 ? sorted.first.key : null;
}

class _Fields {
  final int a, b, c, hour, minute, second;
  final String? ampm;
  final String sender;

  _Fields(RegExpMatch m)
      : a = int.parse(m.group(1)!),
        b = int.parse(m.group(2)!),
        c = int.parse(m.group(3)!),
        hour = int.parse(m.group(4)!),
        minute = int.parse(m.group(5)!),
        second = int.tryParse(m.group(6) ?? '') ?? 0,
        ampm = m.group(7)?.toLowerCase().replaceAll(RegExp(r'[.\s]'), ''),
        sender = m.group(8)!.trim();

  DateTime? toDate({required bool monthFirst, required bool yearFirst}) {
    int y, mo, d;
    if (yearFirst) {
      (y, mo, d) = (a, b, c);
    } else {
      y = c < 100 ? 2000 + c : c;
      (d, mo) = monthFirst ? (b, a) : (a, b);
    }
    var h = hour;
    if (ampm != null) {
      final pm = ampm!.startsWith('p') || ampm!.contains('אחה') || ampm!.contains('אחר');
      if (pm && h < 12) h += 12;
      if (!pm && h == 12) h = 0;
    }
    if (mo < 1 || mo > 12 || d < 1 || d > 31 || h > 23) return null;
    return DateTime(y, mo, d, h, minute, second);
  }
}
