import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';
import 'package:message_hub/app_state.dart';
import 'package:message_hub/core/db.dart';
import 'package:message_hub/core/settings.dart';
import 'package:message_hub/gmail/classifier.dart';
import 'package:message_hub/gmail/gmail_screen.dart';
import 'package:message_hub/gmail/gmail_service.dart';
import 'package:message_hub/main.dart';
import 'package:message_hub/whatsapp/chat_parser.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  testWidgets('all tabs render with sample data on a phone-size screen', (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await initializeDateFormatting('he');
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();

    final state = await tester.runAsync(() async {
      final db = await AppDb.open(path: inMemoryDatabasePath, factory: databaseFactoryFfi);
      final s = AppState(db, await Settings.load(), GmailService());
      final now = DateTime.now();
      s.gmailAddress = 'me@gmail.com';
      s.mail = [
        for (var i = 0; i < 120; i++)
          MailMeta(
            id: '$i',
            sender: i.isEven ? 'deals@store.com' : 'mom@gmail.com',
            senderName: i.isEven ? 'חנות' : 'אמא',
            subject: 'נושא $i',
            date: now.subtract(Duration(hours: i * 7)),
            labels: [if (i % 5 == 0) 'SENT' else 'INBOX', if (i % 3 == 0) 'UNREAD', if (i.isOdd) 'IMPORTANT', if (i == 3) 'STARRED'],
            size: 20000 + i,
            category: i.isEven ? MailCategory.promotions : MailCategory.family,
          ),
      ];
      final d = now.subtract(const Duration(days: 1));
      s.waChats = [
        parseChat('${d.day}/${d.month}/${d.year}, 10:00 - אני: היי\n${d.day}/${d.month}/${d.year}, 10:01 - דנה: מה קורה',
            chatName: 'דנה'),
      ];
      s.settings.waMyName = 'אני';
      return s;
    });

    await tester.pumpWidget(ChangeNotifierProvider.value(value: state!, child: const MessageHubApp()));
    await tester.pumpAndSettle();
    expect(find.text('הודעות ביום'), findsWidgets);

    for (final tab in ['Gmail', 'וואטסאפ', 'SMS', 'הגדרות', 'סקירה']) {
      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(tab)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: tab);
    }

    // Open a category and check the cleanup page renders.
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Gmail')));
    await tester.pumpAndSettle();
    final list = find.descendant(of: find.byType(GmailScreen), matching: find.byType(Scrollable)).first;
    await tester.dragUntilVisible(find.text('פרסומות'), list, const Offset(0, -300));
    await tester.drag(list, const Offset(0, -200)); // move it clear of the navigation bar
    await tester.pumpAndSettle();
    await tester.tap(find.text('פרסומות').first);
    await tester.pumpAndSettle();
    expect(find.byType(MailListPage), findsOneWidget);
    expect(find.text('לאשפה'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Mail from people is usually "important" in Gmail: it must still be listed, just not pre-selected.
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();
    await tester.drag(find.byType(GmailScreen), const Offset(0, 250));
    await tester.pumpAndSettle();
    await tester.tap(find.text('משפחה').first);
    await tester.pumpAndSettle();
    expect(find.byType(CheckboxListTile), findsWidgets);
    expect(find.textContaining('0 נבחרו מתוך'), findsOneWidget);
    expect(find.textContaining('★ '), findsNWidgets(2)); // legend + the starred message
  });
}
