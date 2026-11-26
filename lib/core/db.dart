/// Local SQLite store. Holds only metadata (no e-mail bodies or chat text).
library;

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../gmail/classifier.dart';
import '../whatsapp/chat_parser.dart';

class AppDb {
  final Database db;
  AppDb._(this.db);

  static Future<AppDb> open({String? path, DatabaseFactory? factory}) async {
    final f = factory ?? databaseFactory;
    final dbPath = path ?? p.join(await f.getDatabasesPath(), 'message_hub.db');
    final db = await f.openDatabase(dbPath,
        options: OpenDatabaseOptions(version: 1, onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE gmail (
              id TEXT PRIMARY KEY, sender TEXT, sender_name TEXT, subject TEXT, snippet TEXT,
              date_ms INTEGER, labels TEXT, unsub TEXT, size INTEGER, category TEXT)''');
          await db.execute('CREATE INDEX gmail_date ON gmail(date_ms)');
          await db.execute('CREATE TABLE gmail_contacted (address TEXT PRIMARY KEY)');
          await db.execute('''
            CREATE TABLE wa_messages (
              chat TEXT, ts INTEGER, sender TEXT, media INTEGER, len INTEGER,
              UNIQUE(chat, ts, sender, len))''');
          await db.execute('CREATE TABLE wa_chats (chat TEXT PRIMARY KEY, attachment_bytes INTEGER, imported_ms INTEGER)');
        }));
    return AppDb._(db);
  }

  // ---------------------------------------------------------------- Gmail

  Future<void> upsertMail(List<MailMeta> msgs) async {
    final b = db.batch();
    for (final m in msgs) {
      b.insert('gmail', {
        'id': m.id, 'sender': m.sender, 'sender_name': m.senderName, 'subject': m.subject,
        'snippet': m.snippet, 'date_ms': m.date.millisecondsSinceEpoch,
        'labels': m.labels.join(','), 'unsub': m.listUnsubscribe, 'size': m.size,
        'category': m.category?.name,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await b.commit(noResult: true);
  }

  Future<List<MailMeta>> allMail() async {
    final rows = await db.query('gmail');
    return [
      for (final r in rows)
        MailMeta(
          id: r['id'] as String,
          sender: r['sender'] as String,
          senderName: r['sender_name'] as String,
          subject: r['subject'] as String,
          snippet: r['snippet'] as String,
          date: DateTime.fromMillisecondsSinceEpoch(r['date_ms'] as int),
          labels: (r['labels'] as String).split(',').where((l) => l.isNotEmpty).toList(),
          listUnsubscribe: r['unsub'] as String,
          size: r['size'] as int,
          category: MailCategory.values.asNameMap()[r['category']],
        ),
    ];
  }

  Future<Set<String>> knownMailIds() async =>
      (await db.query('gmail', columns: ['id'])).map((r) => r['id'] as String).toSet();

  Future<void> deleteMail(List<String> ids) async {
    final b = db.batch();
    for (final id in ids) {
      b.delete('gmail', where: 'id = ?', whereArgs: [id]);
    }
    await b.commit(noResult: true);
  }

  Future<void> addContacted(Set<String> addrs) async {
    final b = db.batch();
    for (final a in addrs) {
      b.insert('gmail_contacted', {'address': a}, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await b.commit(noResult: true);
  }

  Future<Set<String>> contacted() async =>
      (await db.query('gmail_contacted')).map((r) => r['address'] as String).toSet();

  Future<void> clearGmail() async {
    await db.delete('gmail');
    await db.delete('gmail_contacted');
  }

  // ---------------------------------------------------------------- WhatsApp exports

  /// Returns how many new messages were stored (re-importing the same chat is safe).
  Future<int> importChat(ParsedChat chat) async {
    var added = 0;
    await db.transaction((tx) async {
      for (final m in chat.messages) {
        final id = await tx.insert('wa_messages', {
          'chat': chat.name, 'ts': m.time.millisecondsSinceEpoch, 'sender': m.sender,
          'media': m.isMedia ? 1 : 0, 'len': m.length,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        if (id != 0) added++;
      }
      await tx.insert('wa_chats', {
        'chat': chat.name, 'attachment_bytes': chat.attachmentBytes,
        'imported_ms': DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
    return added;
  }

  Future<List<ParsedChat>> importedChats() async {
    final chats = await db.query('wa_chats');
    final rows = await db.query('wa_messages', orderBy: 'ts');
    final byChat = <String, List<WaMessage>>{};
    for (final r in rows) {
      byChat.putIfAbsent(r['chat'] as String, () => []).add(WaMessage(
            DateTime.fromMillisecondsSinceEpoch(r['ts'] as int),
            r['sender'] as String,
            isMedia: r['media'] == 1,
            length: r['len'] as int,
          ));
    }
    return [
      for (final c in chats)
        ParsedChat(c['chat'] as String, byChat[c['chat']] ?? const [],
            attachmentBytes: c['attachment_bytes'] as int),
    ];
  }

  Future<void> deleteChat(String name) async {
    await db.delete('wa_messages', where: 'chat = ?', whereArgs: [name]);
    await db.delete('wa_chats', where: 'chat = ?', whereArgs: [name]);
  }
}
