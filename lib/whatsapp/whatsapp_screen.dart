import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../core/format.dart';
import '../core/models.dart';
import '../core/native.dart';
import '../core/stats.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import 'media_scanner.dart';

class WhatsAppScreen extends StatelessWidget {
  const WhatsAppScreen({super.key});

  Future<void> _import(BuildContext context, AppState s) async {
    final files = await FilePicker.pickFiles(
      dialogTitle: 'בחירת צ\'אטים מיוצאים (.txt / .zip)',
      type: FileType.custom,
      allowedExtensions: ['txt', 'zip'],
    );
    if (files.isEmpty) return;
    final loaded = [for (final f in files) (name: f.name, bytes: await f.xFile.readAsBytes())];
    final added = await s.importWhatsAppChats(loaded);
    if (context.mounted && s.error == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('נוספו ${formatCount(added)} הודעות')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final days = s.periodDays;
    final events = s.whatsappEvents;
    final since = DateTime.now().subtract(Duration(days: days));
    final busy = s.progress != null;

    return RefreshIndicator(
      onRefresh: s.refreshWhatsAppNotifications,
      child: ListView(padding: const EdgeInsets.only(top: 12, bottom: 24), children: [
        if (events.isNotEmpty) ...[
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
              if (s.effectiveWaName == null && s.waChats.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('כדי לספור הודעות יוצאות, הגדר את השם שלך בוואטסאפ במסך ההגדרות.',
                      style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
            ]),
          ),
        ],
        if (s.isAndroid) _MediaCard(s),
        if (s.isAndroid) _NotificationCard(s),
        SectionCard(
          title: 'צ\'אטים מיובאים',
          trailing: IconButton.filledTonal(
            tooltip: 'ייבוא',
            onPressed: busy ? null : () => _import(context, s),
            icon: const Icon(Icons.upload_file),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(
              'בוואטסאפ: פתח צ\'אט ← ⋮ (או שם הצ\'אט באייפון) ← עוד ← ייצוא צ\'אט, ושמור את הקובץ. '
              'הייצוא נותן היסטוריה מלאה של הודעות נכנסות ויוצאות. ייצוא "כולל מדיה" (zip) מראה גם כמה מקום תופסים הקבצים.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            for (final c in s.waChats)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(c.isGroup ? Icons.groups_outlined : Icons.person_outline),
                title: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('${formatCount(c.messages.length)} הודעות'
                    '${c.messages.isNotEmpty ? ' · ${formatDate(c.messages.first.time)}–${formatDate(c.messages.last.time)}' : ''}'
                    '${c.attachmentBytes > 0 ? ' · ${formatBytes(c.attachmentBytes)}' : ''}'),
                trailing: IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'הסרה מהאפליקציה',
                  onPressed: () => s.deleteImportedChat(c.name),
                ),
              ),
          ]),
        ),
        if (events.isNotEmpty) ...[
          SectionCard(title: 'צ\'אטים פעילים', child: ContactList(topContacts(events, limit: 10, since: since))),
          SectionCard(title: 'באיזו שעה', child: HourChart(hourHistogram(events, since: since))),
        ],
        if (!s.isAndroid)
          const InfoBox(
            icon: Icons.info_outline,
            title: 'באייפון',
            body: 'iOS לא מאפשר לאפליקציות אחרות לגשת לנתוני וואטסאפ. כדי לראות ולנקות את האחסון: '
                'בוואטסאפ ← הגדרות ← אחסון ונתונים ← ניהול אחסון. שם יש מיון לפי צ\'אט וקבצים גדולים.',
          ),
      ]),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  final AppState s;
  const _NotificationCard(this.s);

  @override
  Widget build(BuildContext context) {
    final today = s.waNotifications.where((n) => dayOf(n.time) == dayOf(DateTime.now())).length;
    return SectionCard(
      title: 'ספירת הודעות נכנסות בזמן אמת',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(
          s.waNotificationAccess
              ? 'פעיל. נספרו ${formatCount(s.waNotifications.length)} הודעות נכנסות, מתוכן $today היום. '
                  'נשמרים רק שם הצ\'אט והשעה, בלי תוכן ההודעה.'
              : 'האפליקציה יכולה לספור הודעות וואטסאפ נכנסות דרך ההתראות. '
                  'הספירה מתחילה מרגע ההפעלה ומונה רק הודעות נכנסות. תוכן ההודעות לא נשמר.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        if (!s.waNotificationAccess) ...[
          const SizedBox(height: 4),
          Text(
            'אם המתג אפור ("הגדרה מוגבלת"): הגדרות ← אפליקציות ← ניהול הודעות ← ⋮ ← "התרת הגדרות מוגבלות", ואז לנסות שוב.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          if (!s.waNotificationAccess)
            FilledButton(
              onPressed: () async {
                await NativeBridge.openNotificationAccessSettings();
              },
              child: const Text('הפעלת גישה להתראות'),
            ),
          OutlinedButton(onPressed: s.refreshWhatsAppNotifications, child: const Text('רענון')),
        ]),
      ]),
    );
  }
}

class _MediaCard extends StatelessWidget {
  final AppState s;
  const _MediaCard(this.s);

  @override
  Widget build(BuildContext context) {
    if (!s.storagePermission) {
      return InfoBox(
        icon: Icons.sd_storage_outlined,
        title: 'אחסון של וואטסאפ',
        body: 'כדי לחשב כמה מקום תופסות התמונות, הסרטונים וההודעות הקוליות של וואטסאפ, ולמחוק קבצים ישנים, '
            'האפליקציה צריכה הרשאת "גישה לכל הקבצים". הסריקה מתבצעת רק בתיקיית המדיה של וואטסאפ.',
        action: FilledButton(
          onPressed: () async {
            if (await s.requestStoragePermission()) await s.scanWhatsAppMedia();
          },
          child: const Text('מתן הרשאה'),
        ),
      );
    }
    final m = s.media;
    if (m == null) {
      return SectionCard(
          title: 'אחסון של וואטסאפ',
          child: FilledButton(onPressed: s.scanWhatsAppMedia, child: const Text('סריקה')));
    }
    if (m.roots.isEmpty) {
      return const InfoBox(icon: Icons.folder_off_outlined, title: 'לא נמצאה תיקיית וואטסאפ', body: 'ייתכן שוואטסאפ לא מותקן בטלפון.');
    }
    final kinds = m.byKind();
    return SectionCard(
      title: 'אחסון של וואטסאפ · ${formatBytes(m.totalBytes)}',
      trailing: IconButton(onPressed: s.scanWhatsAppMedia, icon: const Icon(Icons.refresh), tooltip: 'סריקה מחדש'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        StorageBars(
          [for (final e in kinds.entries) StorageSlice(e.key.label, e.value.bytes, e.value.count)],
          onTap: (slice) {
            final kind = MediaKind.values.firstWhere((k) => k.label == slice.label);
            Navigator.push(context, MaterialPageRoute(builder: (_) => MediaCleanupPage(kind: kind)));
          },
        ),
        const SizedBox(height: 8),
        Text('המספרים לא כוללים את מסד ההודעות הפנימי של וואטסאפ, שאינו נגיש לאפליקציות אחרות.',
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MediaCleanupPage())),
          icon: const Icon(Icons.cleaning_services_outlined),
          label: const Text('ניקוי קבצים'),
        ),
      ]),
    );
  }
}

class MediaCleanupPage extends StatefulWidget {
  final MediaKind? kind;
  const MediaCleanupPage({super.key, this.kind});

  @override
  State<MediaCleanupPage> createState() => _MediaCleanupPageState();
}

class _MediaCleanupPageState extends State<MediaCleanupPage> {
  late Set<MediaKind> kinds = widget.kind == null ? {MediaKind.video, MediaKind.statuses} : {widget.kind!};
  int? olderThan = 90;
  int? minMb;
  bool includeSent = false;
  final Set<String> excluded = {};

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final m = s.media;
    final files = m == null
        ? <MediaFile>[]
        : m.select(kinds: kinds, olderThanDays: olderThan, minBytes: minMb == null ? null : minMb! << 20, sent: includeSent ? null : false);
    final chosen = files.where((f) => !excluded.contains(f.path)).toList();
    final bytes = chosen.fold<int>(0, (a, f) => a + f.size);

    return Scaffold(
      appBar: AppBar(title: const Text('ניקוי מדיה של וואטסאפ')),
      body: Column(children: [
        if (s.progress != null) const LinearProgressIndicator(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Wrap(spacing: 8, runSpacing: 4, children: [
            for (final k in MediaKind.values)
              FilterChip(
                label: Text(k.label),
                selected: kinds.contains(k),
                onSelected: (v) => setState(() => v ? kinds.add(k) : kinds.remove(k)),
              ),
          ]),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(children: [
            for (final d in [null, 30, 90, 365])
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: ChoiceChip(
                  label: Text(d == null ? 'כל הגילים' : 'ישן מ-${d == 365 ? 'שנה' : '$d יום'}'),
                  selected: olderThan == d,
                  onSelected: (_) => setState(() => olderThan = d),
                ),
              ),
            for (final mb in [null, 5, 50])
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: ChoiceChip(
                  label: Text(mb == null ? 'כל גודל' : 'מעל $mb MB'),
                  selected: minMb == mb,
                  onSelected: (_) => setState(() => minMb = mb),
                ),
              ),
            FilterChip(
              label: const Text('כולל קבצים ששלחתי'),
              selected: includeSent,
              onSelected: (v) => setState(() => includeSent = v),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text('${formatCount(chosen.length)} קבצים · ${formatBytes(bytes)}',
              style: Theme.of(context).textTheme.titleSmall),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: files.length,
            itemBuilder: (_, i) {
              final f = files[i];
              return CheckboxListTile(
                dense: true,
                value: !excluded.contains(f.path),
                onChanged: (v) => setState(() => v! ? excluded.remove(f.path) : excluded.add(f.path)),
                title: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('${f.kind.label}${f.sent ? ' (נשלח)' : ''} · ${formatDate(f.modified)}'),
                secondary: Text(formatBytes(f.size)),
              );
            },
          ),
        ),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: chosen.isEmpty || s.progress != null
                ? null
                : () async {
                    if (await confirm(
                        context,
                        'מחיקת ${chosen.length} קבצים',
                        'הקבצים יימחקו מהטלפון לצמיתות (${formatBytes(bytes)}). ההודעות בצ\'אט יישארו, '
                            'אבל הקבצים לא יהיו זמינים בהן, אלא אם יש לך גיבוי.',
                        ok: 'מחיקה',
                        danger: true)) {
                      final (n, freed) = await s.deleteWhatsAppMedia(chosen);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text('נמחקו $n קבצים, התפנו ${formatBytes(freed)}')));
                      }
                    }
                  },
            icon: const Icon(Icons.delete_outline),
            label: Text('מחיקת ${formatBytes(bytes)}'),
          ),
        ),
      ),
    );
  }
}

