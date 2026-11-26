import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../core/edition.dart';
import '../core/format.dart';
import '../core/models.dart';
import '../core/stats.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  static final available = [for (final s in Source.values) if (s != Source.sms || !isLite) s];
  Set<Source> sources = available.toSet();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final days = s.periodDays;
    final events = s.eventsFor(sources);
    final summary = summarize(events, days: days);
    final since = DateTime.now().subtract(Duration(days: days));

    final perSource = {for (final src in Source.values) src: summarize(s.eventsFor({src}), days: days)};
    final gmailBytes = s.mail.fold<int>(0, (a, m) => a + m.size);
    final waMediaBytes = s.media?.totalBytes ?? 0;
    final waExportBytes = s.waChats.fold<int>(0, (a, c) => a + c.attachmentBytes);
    final smsBytes = s.sms.fold<int>(0, (a, m) => a + m.bytes);

    return ListView(padding: const EdgeInsets.only(top: 12, bottom: 24), children: [
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
          Wrap(spacing: 8, children: [
            for (final src in available)
              FilterChip(
                label: Text(src.label),
                selected: sources.contains(src),
                onSelected: (v) => setState(() => v ? sources.add(src) : sources.remove(src)),
              ),
          ]),
          const SizedBox(height: 16),
          SummaryMetrics(summary),
          const SizedBox(height: 16),
          DailyChart(dailySeries(events, days: days)),
          if (summary.busiestDay != null) ...[
            const SizedBox(height: 8),
            Text(
              'היום העמוס ביותר: ${formatDate(summary.busiestDay!.day)} עם ${summary.busiestDay!.total} הודעות',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ]),
      ),
      SectionCard(
        title: 'לפי מקור',
        child: Column(children: [
          for (final src in available)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(switch (src) {
                Source.gmail => Icons.mail_outline,
                Source.whatsapp => Icons.chat_outlined,
                Source.sms => Icons.sms_outlined,
              }),
              title: Text(src.label),
              subtitle: Text(_sourceStatus(s, src, perSource[src]!)),
              trailing: Text(formatCount(perSource[src]!.total), style: Theme.of(context).textTheme.titleMedium),
            ),
        ]),
      ),
      SectionCard(
        title: 'צריכת אחסון',
        child: StorageBars([
          if (s.mail.isNotEmpty) StorageSlice('Gmail (הודעות שנסרקו)', gmailBytes, s.mail.length),
          if (s.media != null) StorageSlice('וואטסאפ – מדיה בטלפון', waMediaBytes, s.media!.files.length),
          if (waExportBytes > 0)
            StorageSlice('וואטסאפ – קבצים בייצוא', waExportBytes, s.waChats.length),
          if (s.sms.isNotEmpty) StorageSlice('SMS / MMS', smsBytes, s.sms.length),
        ]),
      ),
      SectionCard(
        title: 'באיזו שעה',
        child: HourChart(hourHistogram(events, since: since)),
      ),
      SectionCard(
        title: 'אנשי קשר פעילים',
        child: ContactList(topContacts(events, limit: 10, since: since)),
      ),
    ]);
  }

  String _sourceStatus(AppState s, Source src, Summary sum) => switch (src) {
        Source.gmail => s.gmailAddress == null
            ? (s.mail.isEmpty ? 'לא מחובר' : 'נתונים שמורים · לא מחובר')
            : '${s.gmailAddress} · ${formatCount(s.mail.length)} נסרקו',
        Source.whatsapp => [
            if (s.waChats.isNotEmpty) '${s.waChats.length} צ\'אטים מיובאים',
            if (s.waNotificationAccess) 'ספירת התראות פעילה',
            if (s.waChats.isEmpty && !s.waNotificationAccess) 'עוד לא הוגדר',
          ].join(' · '),
        Source.sms => !s.isAndroid
            ? 'לא זמין באייפון'
            : s.smsPermission
                ? '${formatCount(s.sms.length)} הודעות בטלפון'
                : 'נדרשת הרשאה',
      };
}
