import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../core/format.dart';
import '../core/stats.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';

class SmsScreen extends StatelessWidget {
  const SmsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    if (!s.isAndroid) {
      return ListView(padding: const EdgeInsets.only(top: 12), children: const [
        InfoBox(
          icon: Icons.lock_outline,
          title: 'SMS לא זמין באייפון',
          body: 'אפל לא מאפשרת לאף אפליקציה לקרוא הודעות SMS או iMessage. '
              'כדי לראות כמה מקום ההודעות תופסות: הגדרות ← כללי ← אחסון iPhone ← הודעות. '
              'שם אפשר גם להגדיר "שמירת הודעות" ל-30 יום או לשנה, כדי שהישנות יימחקו אוטומטית.',
        ),
      ]);
    }
    if (!s.smsPermission) {
      return ListView(padding: const EdgeInsets.only(top: 12), children: [
        InfoBox(
          icon: Icons.sms_outlined,
          title: 'גישה להודעות SMS',
          body: 'האפליקציה קוראת רק תאריך, כיוון (נכנסת/יוצאת), מספר וגודל של כל הודעה, '
              'לצורך סטטיסטיקה. תוכן ההודעות לא נשמר ולא יוצא מהטלפון. '
              'הרשאת אנשי קשר (אופציונלית) מציגה שמות במקום מספרים.',
          action: FilledButton(onPressed: s.requestSmsPermission, child: const Text('מתן הרשאה')),
        ),
      ]);
    }

    final days = s.periodDays;
    final events = s.smsEvents;
    final since = DateTime.now().subtract(Duration(days: days));
    final inPeriod = s.sms.where((m) => m.time.isAfter(since));
    final mms = inPeriod.where((m) => m.mms).toList();
    final total = s.sms.fold<int>(0, (a, m) => a + m.bytes);
    final mmsBytes = s.sms.where((m) => m.mms).fold<int>(0, (a, m) => a + m.bytes);

    return RefreshIndicator(
      onRefresh: s.loadSms,
      child: ListView(padding: const EdgeInsets.only(top: 12, bottom: 24), children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: PeriodSelector(days: days, onChanged: (d) => s.periodDays = d),
          ),
        ),
        SectionCard(
          title: 'הודעות ביום',
          trailing: const Legend(),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SummaryMetrics(summarize(events, days: days)),
            const SizedBox(height: 16),
            DailyChart(dailySeries(events, days: days)),
          ]),
        ),
        SectionCard(
          title: 'אחסון',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            MetricRow([
              Metric('סה"כ הודעות בטלפון', formatCount(s.sms.length)),
              Metric('נפח משוער', formatBytes(total)),
              Metric('MMS בתקופה', formatCount(mms.length)),
              Metric('נפח MMS', formatBytes(mmsBytes)),
            ]),
            const SizedBox(height: 12),
            Text(
              'מחיקת SMS אפשרית רק מאפליקציית ההודעות הראשית של הטלפון (מגבלה של אנדרואיד). '
              'הרשימה למטה מראה ממי כדאי למחוק שרשורים, למשל קודי אימות ופרסומות.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ]),
        ),
        SectionCard(
          title: 'שולחים ונמענים מובילים',
          child: ContactList(topContacts(events, limit: 15, since: since), showBytes: true),
        ),
        SectionCard(title: 'באיזו שעה', child: HourChart(hourHistogram(events, since: since))),
        SectionCard(
          title: 'שולחים אוטומטיים (קודים, פרסומות)',
          child: ContactList(
            topContacts(s.sms.where((r) => !r.outgoing && isAutomatedSender(r.address)).map((r) => r.toEvent()),
                limit: 10),
          ),
        ),
      ]),
    );
  }
}

/// Senders that are not regular phone numbers: alphanumeric ids ("Leumi") or short codes.
bool isAutomatedSender(String address) {
  final digits = address.replaceAll(RegExp(r'\D'), '');
  return RegExp(r'[A-Za-z\u0590-\u05FF]').hasMatch(address) || digits.length < 7;
}
