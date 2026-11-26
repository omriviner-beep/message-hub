import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../core/format.dart';
import '../core/models.dart';
import '../core/stats.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import 'classifier.dart';
import 'categories_page.dart';
import 'diagnostics_page.dart';

class GmailScreen extends StatelessWidget {
  const GmailScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final busy = s.progress != null;

    if (s.gmailAddress == null) {
      return ListView(padding: const EdgeInsets.only(top: 12), children: [
        InfoBox(
          icon: Icons.mail_outline,
          title: 'חיבור ל-Gmail',
          body: 'האפליקציה מורידה רק כותרות (שולח, נושא, תאריך, גודל), בלי תוכן המיילים, '
              'ושומרת אותן בטלפון בלבד. ההרשאה לא מאפשרת מחיקה לצמיתות: '
              'מיילים מועברים לאשפה ואפשר לשחזר אותם במשך 30 יום.',
          action: FilledButton.icon(
            onPressed: busy ? null : s.connectGmail,
            icon: const Icon(Icons.login),
            label: const Text('התחברות עם Google'),
          ),
        ),
        if (s.mail.isNotEmpty) _GmailBody(s),
      ]);
    }
    return _GmailBody(s, header: true);
  }
}

class _GmailBody extends StatelessWidget {
  final AppState s;
  final bool header;
  const _GmailBody(this.s, {this.header = false});

  @override
  Widget build(BuildContext context) {
    final busy = s.progress != null;
    final days = s.periodDays;
    final events = s.gmailEvents;
    final tax = s.taxonomy;
    final byCat = s.mailByCategory();
    // A parent's numbers include its sub-categories.
    List<MailMeta> inTree(String k) => [for (final x in tax.subtree(k)) ...?byCat[x]];
    final senders = <String, List<MailMeta>>{};
    for (final m in s.mail.where((m) => !m.isSent)) {
      senders.putIfAbsent(m.sender, () => []).add(m);
    }
    final topSenders = senders.entries.toList()..sort((a, b) => b.value.length.compareTo(a.value.length));

    final content = <Widget>[
      if (header)
        SectionCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(s.gmailAddress!, style: Theme.of(context).textTheme.titleMedium),
            Text('${formatCount(s.mail.length)} הודעות נסרקו · שאילתה: ${s.settings.gmailQuery}',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.icon(
                onPressed: busy ? null : () => s.scanGmail(),
                icon: const Icon(Icons.sync),
                label: Text(s.mail.isEmpty ? 'סריקה ראשונה' : 'סריקת חדשות'),
              ),
              OutlinedButton.icon(
                onPressed: busy || s.mail.isEmpty
                    ? null
                    : () async {
                        if (await confirm(context, 'הוספת תוויות ב-Gmail',
                            'ייווצרו תוויות "$gmailLabelPrefix/קבלות", "$gmailLabelPrefix/משפחה" וכו\', והמיילים יסומנו לפי הסיווג. שום מייל לא יימחק.')) {
                          await s.labelMail();
                        }
                      },
                icon: const Icon(Icons.label_outline),
                label: const Text('תיוג ב-Gmail'),
              ),
              TextButton.icon(
                onPressed: busy
                    ? null
                    : () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DiagnosticsPage())),
                icon: const Icon(Icons.network_check),
                label: const Text('בדיקת חיבור'),
              ),
            ]),
          ]),
        ),
      if (s.mail.isNotEmpty) ...[
        SectionCard(
          title: 'מיילים ביום',
          trailing: const Legend(),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: PeriodSelector(days: days, onChanged: (d) => s.periodDays = d),
            ),
            const SizedBox(height: 16),
            SummaryMetrics(summarize(events, days: days)),
            const SizedBox(height: 16),
            DailyChart(dailySeries(events, days: days)),
          ]),
        ),
        SectionCard(
          title: 'סיווג',
          child: Column(children: [
            for (final k in tax.flatTree)
              if (inTree(k).isNotEmpty)
                () {
                  final list = inTree(k);
                  final depth = tax.depth(k);
                  return ListTile(
                    contentPadding: EdgeInsetsDirectional.only(start: 24.0 * depth),
                    leading: Icon(depth > 0 ? Icons.subdirectory_arrow_left : categoryIcon(tax, k)),
                    title: Text(tax.label(k)),
                    subtitle: Text('${list.where((m) => m.isUnread).length} לא נקראו · '
                        '${formatBytes(list.fold(0, (a, m) => a + m.size))}'),
                    trailing: Text(formatCount(list.length), style: Theme.of(context).textTheme.titleMedium),
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => MailListPage(title: tax.path(k), categories: tax.subtree(k)))),
                  );
                }(),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CategoriesPage())),
                icon: const Icon(Icons.tune),
                label: const Text('ניהול קטגוריות'),
              ),
            ),
          ]),
        ),
        SectionCard(
          title: 'אחסון לפי סיווג',
          child: StorageBars([
            for (final k in tax.roots)
              if (inTree(k).isNotEmpty)
                StorageSlice(tax.label(k), inTree(k).fold(0, (a, m) => a + m.size), inTree(k).length),
          ]),
        ),
        SectionCard(
          title: 'השולחים הגדולים',
          child: Column(children: [
            for (final e in topSenders.take(25))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(e.value.first.senderName.isNotEmpty ? e.value.first.senderName : e.key,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  '${e.key} · ${tax.label(e.value.first.category ?? 'other')}'
                  '${e.value.any((m) => m.listUnsubscribe.isNotEmpty) ? ' · רשימת תפוצה' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Text(formatCount(e.value.length)),
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => MailListPage(title: e.key, senders: {e.key}))),
              ),
          ]),
        ),
      ],
      if (header)
        Center(
          child: TextButton(
            onPressed: busy
                ? null
                : () async {
                    if (await confirm(context, 'ניתוק Gmail', 'הנתונים השמורים בטלפון יימחקו. המיילים ב-Gmail לא ישתנו.')) {
                      await s.disconnectGmail();
                    }
                  },
            child: const Text('ניתוק החשבון'),
          ),
        ),
    ];
    if (!header) return Column(children: content);
    return ListView(padding: const EdgeInsets.only(top: 12, bottom: 24), children: content);
  }
}

IconData categoryIcon(Taxonomy tax, String key) => switch (tax.builtIn(key)) {
      MailCategory.family => Icons.family_restroom,
      MailCategory.friends => Icons.people_outline,
      MailCategory.receipts => Icons.receipt_long_outlined,
      MailCategory.finance => Icons.account_balance_outlined,
      MailCategory.travel => Icons.flight_outlined,
      MailCategory.social => Icons.thumb_up_alt_outlined,
      MailCategory.promotions => Icons.local_offer_outlined,
      MailCategory.newsletters => Icons.newspaper_outlined,
      MailCategory.notifications => Icons.notifications_none,
      MailCategory.personal => Icons.person_outline,
      MailCategory.other => Icons.inbox_outlined,
      null => Icons.folder_outlined,
    };

/// Messages of one category or sender, with age filter and trash/archive.
class MailListPage extends StatefulWidget {
  final String title;
  final Set<String>? categories; // keys (already expanded to sub-categories)
  final Set<String>? senders;
  const MailListPage({super.key, required this.title, this.categories, this.senders});

  @override
  State<MailListPage> createState() => _MailListPageState();
}

class _MailListPageState extends State<MailListPage> {
  int? olderThan;
  bool unreadOnly = false;
  final Set<String> excluded = {};
  final Set<String> optedIn = {}; // "important" mail the user ticked by hand

  /// Starred mail is never selectable; Gmail-"important" mail starts unticked.
  bool isChosen(MailMeta m) =>
      !m.isStarred && (m.isImportant ? optedIn.contains(m.id) : !excluded.contains(m.id));

  void toggle(MailMeta m, bool on) {
    if (m.isImportant) {
      on ? optedIn.add(m.id) : optedIn.remove(m.id);
    } else {
      on ? excluded.remove(m.id) : excluded.add(m.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final msgs = s.selectMail(
      categories: widget.categories,
      senders: widget.senders,
      olderThanDays: olderThan,
      unreadOnly: unreadOnly,
      includeImportant: true,
      includeStarred: true,
    );
    final chosen = msgs.where(isChosen).toList();
    final protected = widget.categories?.any(s.taxonomy.isProtected) ?? false;
    final busy = s.progress != null;
    final unsub = msgs.map((m) => m.listUnsubscribe).firstWhere((u) => u.isNotEmpty, orElse: () => '');

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (widget.senders?.length == 1)
            IconButton(
              tooltip: 'סיווג השולח',
              icon: const Icon(Icons.drive_file_move_outline),
              onPressed: () async {
                final sender = widget.senders!.first;
                final tax = s.taxonomy;
                final picked = await pickCategory(context, tax,
                    title: 'לסווג תמיד את $sender כ…',
                    current: tax.senderOverrides[sender],
                    allowAuto: true);
                if (picked == null) return;
                await s.setSenderCategory(sender, picked.isEmpty ? null : picked);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(picked.isEmpty ? 'השולח יסווג אוטומטית' : 'השולח יסווג כ"${tax.path(picked)}"')));
                }
              },
            ),
        ],
      ),
      body: Column(children: [
        if (s.progress != null) LinearProgressIndicator(value: s.progress!.fraction),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(children: [
            for (final d in [null, 30, 90, 365])
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: ChoiceChip(
                  label: Text(d == null ? 'הכול' : 'ישן מ-${d == 365 ? 'שנה' : '$d יום'}'),
                  selected: olderThan == d,
                  onSelected: (_) => setState(() => olderThan = d),
                ),
              ),
            FilterChip(label: const Text('לא נקראו'), selected: unreadOnly, onSelected: (v) => setState(() => unreadOnly = v)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(
            '${formatCount(chosen.length)} נבחרו מתוך ${formatCount(msgs.length)} · '
            '${formatBytes(chosen.fold(0, (a, m) => a + m.size))}\n'
            '★ מסומנים בכוכב: מוגנים ולא ניתנים לבחירה · ❗ "חשוב" לפי Gmail: לא מסומנים מראש',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        if (unsub.isNotEmpty && widget.senders != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: SelectableText('ביטול מנוי: ${unsub.length > 120 ? '${unsub.substring(0, 120)}…' : unsub}',
                style: Theme.of(context).textTheme.bodySmall),
          ),
        Expanded(
          child: ListView.builder(
            itemCount: msgs.length,
            itemBuilder: (_, i) {
              final m = msgs[i];
              return CheckboxListTile(
                dense: true,
                value: isChosen(m),
                onChanged: m.isStarred ? null : (v) => setState(() => toggle(m, v!)),
                title: Text('${m.isStarred ? '★ ' : m.isImportant ? '❗ ' : ''}${m.subject.isEmpty ? '(ללא נושא)' : m.subject}',
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: m.isUnread ? const TextStyle(fontWeight: FontWeight.bold) : null),
                subtitle: Text('${m.senderName.isNotEmpty ? m.senderName : m.sender} · ${formatDate(m.date)}',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              );
            },
          ),
        ),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: busy || chosen.isEmpty
                    ? null
                    : () async {
                        final inbox = chosen.where((m) => m.inInbox).toList();
                        if (await confirm(context, 'ארכוב',
                            '${inbox.length} מיילים יוצאו מתיבת הדואר הנכנס. הם יישארו ב"כל הדואר".')) {
                          await s.archiveMail(inbox);
                        }
                      },
                icon: const Icon(Icons.archive_outlined),
                label: const Text('ארכוב'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
                onPressed: busy || chosen.isEmpty
                    ? null
                    : () async {
                        final warn = protected ? '\n\nשים לב: אלה מיילים מאנשים אמיתיים.' : '';
                        if (await confirm(context, 'העברה לאשפה',
                            '${chosen.length} מיילים יועברו לאשפה של Gmail. אפשר לשחזר אותם משם במשך 30 יום.$warn',
                            ok: 'העבר לאשפה', danger: true)) {
                          await s.trashMail(chosen);
                          if (context.mounted && s.error == null) {
                            ScaffoldMessenger.of(context)
                                .showSnackBar(SnackBar(content: Text('${chosen.length} מיילים הועברו לאשפה')));
                          }
                        }
                      },
                icon: const Icon(Icons.delete_outline),
                label: const Text('לאשפה'),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
