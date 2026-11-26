import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:material_ui/material_ui.dart';

import '../core/format.dart';
import '../core/models.dart';

const incomingColor = Color(0xFF2A6FDB);
const outgoingColor = Color(0xFFE07A1F);

class Legend extends StatelessWidget {
  const Legend({super.key});

  @override
  Widget build(BuildContext context) {
    Widget dot(Color c, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 4),
          Text(t, style: Theme.of(context).textTheme.bodySmall),
        ]);
    return Wrap(spacing: 16, children: [dot(incomingColor, 'נכנסות'), dot(outgoingColor, 'יוצאות')]);
  }
}

/// Stacked bars: incoming (bottom) + outgoing (top) per day.
class DailyChart extends StatelessWidget {
  final List<DailyStat> series;
  final double height;
  const DailyChart(this.series, {super.key, this.height = 200});

  @override
  Widget build(BuildContext context) {
    if (series.isEmpty) return SizedBox(height: height);
    final maxY = series.map((s) => s.total).fold(0, math.max).toDouble();
    final labelEvery = (series.length / 6).ceil().clamp(1, 1000);
    final barWidth = (280 / series.length).clamp(2.0, 18.0);
    final muted = Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 10);
    return Directionality(
      // time flows left-to-right even in a Hebrew UI
      textDirection: TextDirection.ltr,
      child: SizedBox(
        height: height,
        child: BarChart(BarChartData(
          maxY: maxY == 0 ? 1 : maxY * 1.15,
          alignment: BarChartAlignment.spaceBetween,
          gridData: FlGridData(drawVerticalLine: false, horizontalInterval: _niceInterval(maxY)),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 36,
                interval: _niceInterval(maxY),
                getTitlesWidget: (v, meta) =>
                    SideTitleWidget(meta: meta, child: Text(formatCount(v.round()), style: muted)),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                getTitlesWidget: (v, meta) {
                  final i = v.toInt();
                  if (i < 0 || i >= series.length || (series.length - 1 - i) % labelEvery != 0) {
                    return const SizedBox.shrink();
                  }
                  return SideTitleWidget(meta: meta, child: Text(formatDay(series[i].day), style: muted));
                },
              ),
            ),
          ),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => Theme.of(context).colorScheme.inverseSurface,
              getTooltipItem: (group, _, _, _) {
                final s = series[group.x];
                return BarTooltipItem(
                  '${formatDate(s.day)}\nנכנסות ${s.incoming} · יוצאות ${s.outgoing}',
                  TextStyle(color: Theme.of(context).colorScheme.onInverseSurface, fontSize: 12),
                  textDirection: TextDirection.rtl,
                );
              },
            ),
          ),
          barGroups: [
            for (var i = 0; i < series.length; i++)
              BarChartGroupData(x: i, barRods: [
                BarChartRodData(
                  toY: series[i].total.toDouble(),
                  width: barWidth,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                  rodStackItems: [
                    BarChartRodStackItem(0, series[i].incoming.toDouble(), incomingColor),
                    BarChartRodStackItem(series[i].incoming.toDouble(), series[i].total.toDouble(), outgoingColor),
                  ],
                ),
              ]),
          ],
        )),
      ),
    );
  }
}

double _niceInterval(double maxY) {
  if (maxY <= 5) return 1;
  final raw = maxY / 4;
  final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
  for (final m in [1, 2, 5, 10]) {
    if (raw <= m * mag) return m * mag;
  }
  return 10 * mag;
}

/// 24 bars - messages by hour of day.
class HourChart extends StatelessWidget {
  final List<int> hours;
  const HourChart(this.hours, {super.key});

  @override
  Widget build(BuildContext context) {
    final maxY = hours.fold(0, math.max).toDouble();
    final muted = Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 10);
    final color = Theme.of(context).colorScheme.primary;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox(
        height: 120,
        child: BarChart(BarChartData(
          maxY: maxY == 0 ? 1 : maxY * 1.1,
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (g, _, rod, _) => BarTooltipItem(
                  '${g.x}:00 · ${rod.toY.toInt()}', const TextStyle(color: Colors.white, fontSize: 12)),
            ),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: const AxisTitles(),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 20,
                getTitlesWidget: (v, meta) => v.toInt() % 6 == 0
                    ? SideTitleWidget(meta: meta, child: Text('${v.toInt()}:00', style: muted))
                    : const SizedBox.shrink(),
              ),
            ),
          ),
          barGroups: [
            for (var h = 0; h < 24; h++)
              BarChartGroupData(x: h, barRods: [
                BarChartRodData(
                    toY: hours[h].toDouble(),
                    color: color,
                    width: 7,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(2))),
              ]),
          ],
        )),
      ),
    );
  }
}

/// Horizontal bars for storage slices, largest first.
class StorageBars extends StatelessWidget {
  final List<StorageSlice> slices;
  final void Function(StorageSlice)? onTap;
  const StorageBars(this.slices, {super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    final sorted = [...slices]..sort((a, b) => b.bytes.compareTo(a.bytes));
    final max = sorted.isEmpty ? 1 : math.max(1, sorted.first.bytes);
    final theme = Theme.of(context);
    return Column(children: [
      for (final s in sorted)
        InkWell(
          onTap: onTap == null ? null : () => onTap!(s),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(s.label, style: theme.textTheme.bodyMedium)),
                Text('${formatBytes(s.bytes)} · ${formatCount(s.count)}', style: theme.textTheme.bodySmall),
              ]),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: s.bytes / max,
                  minHeight: 8,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                ),
              ),
            ]),
          ),
        ),
    ]);
  }
}
