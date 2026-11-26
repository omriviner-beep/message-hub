import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../core/format.dart';
import '../core/settings.dart';
import '../widgets/common.dart';
import 'classifier.dart';
import 'gmail_screen.dart' show categoryIcon;

/// Bottom sheet listing every category as a tree. Returns the key,
/// '' for "automatic" (when [allowAuto]), or null if dismissed.
Future<String?> pickCategory(
  BuildContext context,
  Taxonomy tax, {
  required String title,
  String? current,
  bool allowAuto = false,
  bool allowNone = false,
  Set<String> exclude = const {},
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      builder: (c, scroll) => ListView(controller: scroll, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(title, style: Theme.of(c).textTheme.titleMedium),
        ),
        if (allowAuto)
          ListTile(
            leading: const Icon(Icons.auto_awesome_outlined),
            title: const Text('אוטומטי (לפי החוקים)'),
            selected: current == null,
            onTap: () => Navigator.pop(c, ''),
          ),
        if (allowNone)
          ListTile(
            leading: const Icon(Icons.vertical_align_top),
            title: const Text('ללא – קטגוריה ראשית'),
            selected: current == null,
            onTap: () => Navigator.pop(c, ''),
          ),
        for (final k in tax.flatTree)
          if (!exclude.contains(k))
            ListTile(
              contentPadding: EdgeInsetsDirectional.only(start: 16 + 24.0 * tax.depth(k), end: 16),
              leading: Icon(categoryIcon(tax, k)),
              title: Text(tax.label(k)),
              selected: current == k,
              onTap: () => Navigator.pop(c, k),
            ),
      ]),
    ),
  );
}

class CategoriesPage extends StatelessWidget {
  const CategoriesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final tax = s.taxonomy;
    final counts = {for (final e in s.mailByCategory().entries) e.key: e.value.length};
    int countTree(String k) => tax.subtree(k).fold(0, (a, x) => a + (counts[x] ?? 0));
    final overrides = tax.senderOverrides.entries.toList()..sort((a, b) => a.key.compareTo(b.key));

    return Scaffold(
      appBar: AppBar(title: const Text('ניהול קטגוריות')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CategoryEditor())),
        icon: const Icon(Icons.add),
        label: const Text('קטגוריה חדשה'),
      ),
      body: ListView(padding: const EdgeInsets.only(top: 12, bottom: 96), children: [
        if (s.progress != null) const LinearProgressIndicator(),
        SectionCard(
          title: 'הקטגוריות שלי',
          child: tax.customs.isEmpty
              ? Text(
                  'אין עדיין. אפשר ליצור קטגוריה ראשית (למשל "עבודה" לפי דומיין החברה), '
                  'או תת-קטגוריה (למשל "קבלות ← אמזון").',
                  style: Theme.of(context).textTheme.bodyMedium,
                )
              : Column(children: [
                  for (final k in tax.flatTree)
                    if (tax.custom(k) != null)
                      ListTile(
                        contentPadding: EdgeInsetsDirectional.only(start: 24.0 * tax.depth(k)),
                        leading: Icon(tax.depth(k) > 0 ? Icons.subdirectory_arrow_left : Icons.folder_outlined),
                        title: Text(tax.path(k)),
                        subtitle: Text(_rulesSummary(tax.custom(k)!)),
                        trailing: Text(formatCount(countTree(k))),
                        onTap: () => Navigator.push(
                            context, MaterialPageRoute(builder: (_) => CategoryEditor(existing: tax.custom(k)))),
                      ),
                ]),
        ),
        SectionCard(
          title: 'קטגוריות מובנות',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('קטגוריה כבויה לא מופיעה, והמיילים שלה עוברים לקטגוריה המתאימה הבאה.',
                style: Theme.of(context).textTheme.bodySmall),
            for (final c in MailCategory.values)
              if (c != MailCategory.other)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: Icon(categoryIcon(tax, c.name)),
                  title: Text(c.label),
                  subtitle: tax.disabled.contains(c) ? const Text('כבויה') : Text('${formatCount(countTree(c.name))} מיילים'),
                  value: !tax.disabled.contains(c),
                  onChanged: s.progress != null ? null : (v) => s.setCategoryEnabled(c, v),
                ),
          ]),
        ),
        if (overrides.isNotEmpty)
          SectionCard(
            title: 'שולחים עם סיווג קבוע',
            child: Column(children: [
              for (final e in overrides)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(e.key, textDirection: TextDirection.ltr, textAlign: TextAlign.start),
                  subtitle: Text(tax.exists(e.value) ? tax.path(e.value) : '(קטגוריה לא פעילה)'),
                  trailing: IconButton(
                    tooltip: 'ביטול',
                    icon: const Icon(Icons.close),
                    onPressed: () => s.setSenderCategory(e.key, null),
                  ),
                ),
            ]),
          ),
        const InfoBox(
          icon: Icons.info_outline,
          title: 'איך זה עובד',
          body: 'סדר העדיפויות: שולח עם סיווג קבוע ← קטגוריה ראשית שלך שהחוקים שלה מתאימים ← הקטגוריות המובנות. '
              'אחר כך המייל עובר לתת-הקטגוריה המתאימה ביותר. למשל, תת-קטגוריה "אמזון" תחת "קבלות" תופסת רק קבלות מאמזון, '
              'ולא פרסומות מאמזון.\n\nלסיווג קבוע של שולח: Gmail ← "השולחים הגדולים" ← בחירת שולח ← סמל התיקייה למעלה.',
        ),
      ]),
    );
  }
}

String _rulesSummary(CustomCategory c) {
  final parts = [
    if (c.senders.isNotEmpty) '${c.senders.length} שולחים',
    if (c.domains.isNotEmpty) c.domains.take(2).join(', ') + (c.domains.length > 2 ? '…' : ''),
    if (c.keywords.isNotEmpty) 'מילים: ${c.keywords.take(3).join(', ')}${c.keywords.length > 3 ? '…' : ''}',
  ];
  return parts.isEmpty ? 'אין חוקים – לא יתפוס מיילים' : parts.join(' · ');
}

class CategoryEditor extends StatefulWidget {
  final CustomCategory? existing;
  const CategoryEditor({super.key, this.existing});

  @override
  State<CategoryEditor> createState() => _CategoryEditorState();
}

class _CategoryEditorState extends State<CategoryEditor> {
  late final e = widget.existing;
  late final name = TextEditingController(text: e?.name ?? '');
  late final senders = TextEditingController(text: e?.senders.join('\n') ?? '');
  late final domains = TextEditingController(text: e?.domains.join('\n') ?? '');
  late final keywords = TextEditingController(text: e?.keywords.join(', ') ?? '');
  late String? parent = e?.parent;
  late bool protected = e?.protected ?? false;

  CustomCategory _build() => CustomCategory(
        id: e?.id ?? 'c_${DateTime.now().millisecondsSinceEpoch}',
        name: name.text.trim(),
        parent: parent,
        senders: splitList(senders.text).map((x) => x.toLowerCase()).toList(),
        domains: splitList(domains.text).map((x) => x.toLowerCase()).toList(),
        keywords: splitList(keywords.text),
        protected: protected,
      );

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final tax = s.taxonomy;
    final draft = _build();
    final preview = name.text.trim().isEmpty || !draft.hasRules ? null : s.mail.where((m) => !m.isSent && draft.matches(m)).toList();
    InputDecoration dec(String label, [String? hint]) =>
        InputDecoration(labelText: label, hintText: hint, border: const OutlineInputBorder());

    return Scaffold(
      appBar: AppBar(
        title: Text(e == null ? 'קטגוריה חדשה' : 'עריכת קטגוריה'),
        actions: [
          if (e != null)
            IconButton(
              tooltip: 'מחיקה',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final kids = tax.childrenOf(e!.id).length;
                if (await confirm(
                    context,
                    'מחיקת "${e!.name}"',
                    'הקטגוריה תימחק והמיילים שלה יסווגו מחדש. שום מייל לא יימחק.'
                        '${kids > 0 ? '\nתתי-הקטגוריות שלה ($kids) יעברו רמה אחת למעלה.' : ''}',
                    ok: 'מחיקה',
                    danger: true)) {
                  await s.deleteCustomCategory(e!.id);
                  if (context.mounted) Navigator.pop(context);
                }
              },
            ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(controller: name, decoration: dec('שם'), onChanged: (_) => setState(() {})),
        const SizedBox(height: 12),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.account_tree_outlined),
          title: const Text('מיקום'),
          subtitle: Text(parent == null ? 'קטגוריה ראשית' : 'תת-קטגוריה של "${tax.path(parent!)}"'),
          trailing: const Icon(Icons.chevron_left),
          onTap: () async {
            final p = await pickCategory(context, tax,
                title: 'תחת איזו קטגוריה?',
                current: parent,
                allowNone: true,
                exclude: e == null ? const {} : tax.subtree(e!.id));
            if (p != null) setState(() => parent = p.isEmpty ? null : p);
          },
        ),
        if (parent != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('תתפוס רק מיילים שכבר סווגו ל"${tax.path(parent!)}" ומתאימים לחוקים למטה.',
                style: Theme.of(context).textTheme.bodySmall),
          ),
        const SizedBox(height: 8),
        Text('חוקים (מספיק שאחד מתאים)', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        TextField(
          controller: domains,
          maxLines: 3,
          textDirection: TextDirection.ltr,
          decoration: dec('דומיינים של השולח', 'amazon.com (אחד בכל שורה)'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: senders,
          maxLines: 3,
          textDirection: TextDirection.ltr,
          decoration: dec('כתובות שולחים', 'boss@company.com'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: keywords,
          decoration: dec('מילים בנושא המייל', 'חשבונית, משלוח'),
          onChanged: (_) => setState(() {}),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: protected,
          onChanged: (v) => setState(() => protected = v),
          title: const Text('מוגנת'),
          subtitle: const Text('מיילים מאנשים – אזהרה נוספת לפני מחיקה'),
        ),
        if (preview != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              parent == null
                  ? 'החוקים מתאימים ל-${formatCount(preview.length)} מיילים שנסרקו'
                  : 'החוקים מתאימים ל-${formatCount(preview.length)} מיילים שנסרקו (מתוכם ייכנסו רק אלה שב"${tax.label(parent!)}")',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: name.text.trim().isEmpty || s.progress != null
              ? null
              : () async {
                  await s.saveCustomCategory(_build());
                  if (context.mounted) Navigator.pop(context);
                },
          child: const Text('שמירה'),
        ),
      ]),
    );
  }
}
