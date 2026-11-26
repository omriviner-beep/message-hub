import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:message_hub/core/db.dart';
import 'package:message_hub/core/models.dart';
import 'package:message_hub/core/native.dart';
import 'package:message_hub/core/stats.dart';
import 'package:message_hub/gmail/classifier.dart';
import 'package:message_hub/gmail/gmail_service.dart';
import 'package:message_hub/sms/sms_screen.dart' show isAutomatedSender;
import 'package:message_hub/whatsapp/chat_parser.dart';
import 'package:message_hub/whatsapp/media_scanner.dart';
import 'package:message_hub/whatsapp/wa_events.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

MsgEvent ev(DateTime t, {bool out = false, String c = 'x', int b = 0}) =>
    MsgEvent(time: t, outgoing: out, source: Source.sms, contact: c, bytes: b);

void main() {
  group('stats', () {
    final now = DateTime(2026, 11, 26, 15);
    final events = [
      ev(DateTime(2026, 11, 26, 9)),
      ev(DateTime(2026, 11, 26, 10), out: true, c: 'y'),
      ev(DateTime(2026, 11, 24, 23, 59), b: 100),
      ev(DateTime(2026, 11, 20), b: 999), // outside 7-day window? (20..26 is 7 days) -> inside
      ev(DateTime(2026, 11, 19)), // outside
    ];

    test('daily series is zero-filled and oldest first', () {
      final s = dailySeries(events, days: 7, now: now);
      expect(s.length, 7);
      expect(s.first.day, DateTime(2026, 11, 20));
      expect(s.last.day, DateTime(2026, 11, 26));
      expect(s.last.incoming, 1);
      expect(s.last.outgoing, 1);
      expect(s[4].total, 1); // 24th
      expect(s[5].total, 0);
    });

    test('summary', () {
      final sum = summarize(events, days: 7, now: now);
      expect(sum.total, 4);
      expect(sum.outgoing, 1);
      expect(sum.today, 2);
      expect(sum.bytes, 1099);
      expect(sum.busiestDay!.day, DateTime(2026, 11, 26));
    });

    test('series across DST change keeps one bar per day', () {
      final s = dailySeries([], days: 60, now: DateTime(2026, 11, 26));
      expect(s.map((d) => d.day).toSet().length, 60);
      expect(s.every((d) => d.day.hour == 0), isTrue);
    });

    test('top contacts and hours', () {
      final t = topContacts(events);
      expect(t.first.contact, 'x');
      expect(t.first.incoming, 4);
      expect(hourHistogram(events)[9], 1);
    });
  });

  group('gmail classifier', () {
    final clf = MailClassifier(
      const ClassifierConfig(
        myAddresses: {'me@gmail.com'},
        familyAddresses: {'mom@gmail.com'},
        familyNames: ['כהן'],
        friendAddresses: {'buddy@yahoo.com'},
        extraRules: {MailCategory.promotions: Rules(domains: ['myshop.co.il'])},
      ),
      contacted: {'dana@gmail.com', 'me@gmail.com'},
    );
    MailMeta m(String from, String subject, {String name = '', List<String> labels = const [], String unsub = ''}) =>
        MailMeta(id: from + subject, sender: from, senderName: name, subject: subject, date: DateTime(2026), labels: labels, listUnsubscribe: unsub);

    final cases = <MailMeta, MailCategory>{
      m('mom@gmail.com', 'מה שלומך'): MailCategory.family,
      m('yossi@walla.co.il', 'ארוחת שישי', name: 'יוסי כהן'): MailCategory.family,
      m('buddy@yahoo.com', 'hey'): MailCategory.friends,
      m('dana@gmail.com', 'נפגשים?'): MailCategory.friends,
      m('stranger@gmail.com', 'שאלה'): MailCategory.personal,
      m('orders@shop.com', 'Your receipt from Shop', unsub: '<x>'): MailCategory.receipts,
      m('noreply@wolt.com', 'קבלה עבור הזמנתך'): MailCategory.receipts,
      m('service@isracard.co.il', 'פירוט חיובים'): MailCategory.finance,
      m('alerts@bank.example', 'דף חשבון חודשי'): MailCategory.finance,
      m('noreply@booking.com', 'Booking confirmation'): MailCategory.travel,
      m('notification@facebookmail.com', 'New friend'): MailCategory.social,
      m('deals@store.com', '50% off today', unsub: '<x>'): MailCategory.promotions,
      m('news@store.com', 'Our story', labels: ['CATEGORY_PROMOTIONS']): MailCategory.promotions,
      m('hi@myshop.co.il', 'חדש'): MailCategory.promotions,
      m('digest@substack.com', 'Weekly', unsub: '<x>'): MailCategory.newsletters,
      m('no-reply@github.com', '[repo] issue'): MailCategory.notifications,
      m('me@gmail.com', 're: hi', labels: ['SENT']): MailCategory.other,
      m('news@cohen-shop.com', 'מבצע', name: 'חנות כהן', unsub: '<x>'): MailCategory.promotions,
    };
    cases.forEach((msg, expected) {
      test('${msg.sender} -> ${expected.name}', () => expect(clf.classify(msg), expected));
    });
  });

  group('addresses', () {
    test('parseAddress', () {
      expect(parseAddress('"Dana Levi" <Dana@Gmail.com>'), ('Dana Levi', 'dana@gmail.com'));
      expect(parseAddress('שירות <noreply@x.co.il>'), ('שירות', 'noreply@x.co.il'));
      expect(parseAddress('a@b.com'), ('', 'a@b.com'));
    });
    test('parseAddressList handles commas inside quotes', () {
      expect(parseAddressList('"Levi, Dana" <d@x.com>, b@y.com'), {'d@x.com', 'b@y.com'});
    });
    test('normalizePhone', () {
      expect(normalizePhone('+972 50-123-4567'), '0501234567');
      expect(normalizePhone('972501234567'), '0501234567');
      expect(normalizePhone('050-1234567'), '0501234567');
    });
    test('automated SMS senders', () {
      expect(isAutomatedSender('Leumi'), isTrue);
      expect(isAutomatedSender('בנק'), isTrue);
      expect(isAutomatedSender('5566'), isTrue);
      expect(isAutomatedSender('0501234567'), isFalse);
    });
  });

  group('whatsapp chat parser', () {
    test('Android Hebrew, 24h, day-first, with RTL marks and multi-line', () {
      const txt = '13/11/2026, 21:05 - ההודעות והשיחות מוצפנות מקצה לקצה.\n'
          '‏13/11/2026, 21:06 - אמא: מה נשמע?\n'
          'שורה שנייה של אותה הודעה\n'
          '14/11/2026, 08:00 - אני: <המדיה לא נכללה>\n';
      final c = parseChat(txt, chatName: 'אמא');
      expect(c.messages.length, 2);
      expect(c.messages[0].time, DateTime(2026, 11, 13, 21, 6));
      expect(c.messages[0].sender, 'אמא');
      expect(c.messages[1].isMedia, isTrue);
    });

    test('Android US 12h month-first', () {
      const txt = '11/13/26, 9:05 PM - John: Hi\n11/14/26, 12:30 AM - Me: yo\n';
      final c = parseChat(txt, chatName: 'John');
      expect(c.messages[0].time, DateTime(2026, 11, 13, 21, 5));
      expect(c.messages[1].time, DateTime(2026, 11, 14, 0, 30));
    });

    test('iPhone bracket format with seconds', () {
      const txt = '[13.11.2026, 21:05:33] Dana: hello\n[13.11.2026, 21:06:00] Me: ‎image omitted\n';
      final c = parseChat(txt, chatName: 'Dana');
      expect(c.messages.length, 2);
      expect(c.messages[0].time, DateTime(2026, 11, 13, 21, 5, 33));
      expect(c.messages[1].isMedia, isTrue);
    });

    test('chat name from file name', () {
      expect(chatNameFromFile('WhatsApp Chat with Dana Levi.txt'), 'Dana Levi');
      expect(chatNameFromFile("צ'אט WhatsApp עם משפחה (1).zip"), 'משפחה');
    });

    test('guessMyName picks the sender present in every chat', () {
      final a = parseChat('1/1/2026, 10:00 - Me: a\n1/1/2026, 10:01 - Dana: b\n', chatName: 'Dana');
      final b = parseChat('1/1/2026, 10:00 - Me: a\n1/1/2026, 10:01 - Yossi: b\n', chatName: 'Yossi');
      expect(guessMyName([a, b]), 'Me');
      expect(guessMyName([a]), isNull);
    });

    test('notifications already covered by an export are not double counted', () {
      final chat = parseChat('1/11/2026, 10:00 - Me: a\n2/11/2026, 10:01 - Dana: b\n', chatName: 'Dana');
      final events = whatsAppEvents(chats: [chat], myName: 'Me', notifications: [
        WaNotification(DateTime(2026, 11, 2, 10, 1), 'Dana', 'Dana'), // duplicate of export
        WaNotification(DateTime(2026, 11, 3, 9), 'Dana', 'Dana'), // newer - counted
        WaNotification(DateTime(2026, 11, 1, 9), 'Group', 'Avi'), // other chat - counted
      ]);
      expect(events.length, 4);
      expect(events.where((e) => e.outgoing).length, 1);
    });
  });

  group('media scanner', () {
    late Directory root;
    setUp(() {
      root = Directory.systemTemp.createTempSync('wa');
      File('${root.path}/WhatsApp Images/IMG-1.jpg')..createSync(recursive: true)..writeAsBytesSync(List.filled(1000, 0));
      File('${root.path}/WhatsApp Images/Sent/IMG-2.jpg')..createSync(recursive: true)..writeAsBytesSync(List.filled(500, 0));
      File('${root.path}/WhatsApp Video/VID-1.mp4')..createSync(recursive: true)..writeAsBytesSync(List.filled(5000, 0));
      File('${root.path}/WhatsApp Video/.nomedia').createSync();
      File('${root.path}/WhatsApp Video/VID-1.mp4').setLastModifiedSync(DateTime(2020));
    });
    tearDown(() => root.deleteSync(recursive: true));

    test('groups by kind, detects sent, filters and deletes', () async {
      final scan = scanMedia([root.path, '/does/not/exist']);
      expect(scan.roots, [root.path]);
      expect(scan.totalBytes, 6500);
      expect(scan.byKind()[MediaKind.images]!.count, 2);
      expect(scan.files.where((f) => f.sent).single.name, 'IMG-2.jpg');
      final old = scan.select(olderThanDays: 365);
      expect(old.single.kind, MediaKind.video);
      expect(scan.select(kinds: {MediaKind.images}, sent: false).single.name, 'IMG-1.jpg');
      final (n, freed) = await deleteMedia(old);
      expect((n, freed), (1, 5000));
      expect(scanMedia([root.path]).totalBytes, 1500);
    });
  });

  group('database', () {
    late AppDb db;
    setUp(() async {
      sqfliteFfiInit();
      db = await AppDb.open(path: inMemoryDatabasePath, factory: databaseFactoryFfi);
    });

    test('mail round trip keeps category and labels', () async {
      await db.upsertMail([
        MailMeta(id: '1', sender: 'a@b.com', date: DateTime(2026, 1, 2), labels: ['INBOX', 'UNREAD'], category: MailCategory.receipts, size: 10),
      ]);
      final all = await db.allMail();
      expect(all.single.category, MailCategory.receipts);
      expect(all.single.labels, ['INBOX', 'UNREAD']);
      all.single.labels.remove('INBOX'); // must be growable
      await db.deleteMail(['1']);
      expect(await db.allMail(), isEmpty);
    });

    test('re-importing the same chat adds nothing', () async {
      final chat = parseChat('1/11/2026, 10:00 - Me: a\n2/11/2026, 10:01 - Dana: b\n', chatName: 'Dana');
      expect(await db.importChat(chat), 2);
      expect(await db.importChat(chat), 0);
      final chats = await db.importedChats();
      expect(chats.single.messages.length, 2);
    });
  });
}
