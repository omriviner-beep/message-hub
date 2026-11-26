import 'package:material_ui/material_ui.dart';

import '../core/format.dart';
import '../core/models.dart';

class SectionCard extends StatelessWidget {
  final String? title;
  final Widget child;
  final Widget? trailing;
  const SectionCard({super.key, this.title, required this.child, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(children: [
                Expanded(child: Text(title!, style: Theme.of(context).textTheme.titleMedium)),
                ?trailing,
              ]),
            ),
          child,
        ]),
      ),
    );
  }
}

class Metric extends StatelessWidget {
  final String label;
  final String value;
  const Metric(this.label, this.value, {super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(value, style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
      Text(label, style: t.bodySmall),
    ]);
  }
}

/// Wrap of metrics that reflows on narrow phones.
class MetricRow extends StatelessWidget {
  final List<Metric> metrics;
  const MetricRow(this.metrics, {super.key});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, c) {
          final cols = c.maxWidth > 500 ? metrics.length : 2;
          final w = (c.maxWidth - (cols - 1) * 12) / cols;
          return Wrap(spacing: 12, runSpacing: 12, children: [
            for (final m in metrics) SizedBox(width: w, child: m),
          ]);
        },
      );
}

class SummaryMetrics extends StatelessWidget {
  final Summary s;
  const SummaryMetrics(this.s, {super.key});

  @override
  Widget build(BuildContext context) => MetricRow([
        Metric('נכנסות', formatCount(s.incoming)),
        Metric('יוצאות', formatCount(s.outgoing)),
        Metric('ממוצע ליום', s.avgPerDay.toStringAsFixed(s.avgPerDay < 10 ? 1 : 0)),
        Metric('היום', formatCount(s.today)),
      ]);
}

class PeriodSelector extends StatelessWidget {
  final int days;
  final ValueChanged<int> onChanged;
  const PeriodSelector({super.key, required this.days, required this.onChanged});

  @override
  Widget build(BuildContext context) => SegmentedButton<int>(
        segments: const [
          ButtonSegment(value: 7, label: Text('שבוע')),
          ButtonSegment(value: 30, label: Text('חודש')),
          ButtonSegment(value: 90, label: Text('3 חודשים')),
          ButtonSegment(value: 365, label: Text('שנה')),
        ],
        selected: {days},
        showSelectedIcon: false,
        onSelectionChanged: (s) => onChanged(s.first),
      );
}

/// Explains why a feature is unavailable (e.g. SMS on iPhone).
class InfoBox extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final Widget? action;
  const InfoBox({super.key, required this.icon, required this.title, required this.body, this.action});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return SectionCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: t.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: t.textTheme.titleMedium)),
        ]),
        const SizedBox(height: 8),
        Text(body, style: t.textTheme.bodyMedium),
        if (action != null) ...[const SizedBox(height: 12), Align(alignment: AlignmentDirectional.centerStart, child: action)],
      ]),
    );
  }
}

class ContactList extends StatelessWidget {
  final List<ContactStat> contacts;
  final bool showBytes;
  final void Function(ContactStat)? onTap;
  const ContactList(this.contacts, {super.key, this.showBytes = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    if (contacts.isEmpty) return const Text('אין נתונים בתקופה הזו');
    return Column(children: [
      for (final c in contacts)
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          onTap: onTap == null ? null : () => onTap!(c),
          title: Text(c.contact, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text('נכנסות ${formatCount(c.incoming)} · יוצאות ${formatCount(c.outgoing)}'
              '${showBytes ? ' · ${formatBytes(c.bytes)}' : ''}'),
          trailing: Text(formatCount(c.total), style: Theme.of(context).textTheme.titleMedium),
        ),
    ]);
  }
}

Future<bool> confirm(BuildContext context, String title, String body, {String ok = 'אישור', bool danger = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('ביטול')),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: Theme.of(c).colorScheme.error) : null,
          onPressed: () => Navigator.pop(c, true),
          child: Text(ok),
        ),
      ],
    ),
  );
  return r ?? false;
}
