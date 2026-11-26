import 'models.dart';

DateTime dayOf(DateTime t) => DateTime(t.year, t.month, t.day);

/// Incoming/outgoing counts per calendar day for the last [days] days
/// (including today), with zero-filled gaps. Oldest first.
List<DailyStat> dailySeries(Iterable<MsgEvent> events, {required int days, DateTime? now}) {
  final today = dayOf(now ?? DateTime.now());
  final start = DateTime(today.year, today.month, today.day - (days - 1));
  final inc = <DateTime, int>{};
  final out = <DateTime, int>{};
  for (final e in events) {
    final d = dayOf(e.time);
    if (d.isBefore(start) || d.isAfter(today)) continue;
    final m = e.outgoing ? out : inc;
    m[d] = (m[d] ?? 0) + 1;
  }
  return [
    for (var i = 0; i < days; i++)
      () {
        final d = DateTime(start.year, start.month, start.day + i);
        return DailyStat(d, inc[d] ?? 0, out[d] ?? 0);
      }(),
  ];
}

Summary summarize(Iterable<MsgEvent> events, {required int days, DateTime? now}) {
  final series = dailySeries(events, days: days, now: now);
  var incoming = 0, outgoing = 0;
  DailyStat? busiest;
  for (final s in series) {
    incoming += s.incoming;
    outgoing += s.outgoing;
    if (s.total > 0 && (busiest == null || s.total > busiest.total)) busiest = s;
  }
  final start = series.isEmpty ? DateTime(0) : series.first.day;
  var bytes = 0;
  for (final e in events) {
    if (!dayOf(e.time).isBefore(start)) bytes += e.bytes;
  }
  return Summary(
    incoming: incoming,
    outgoing: outgoing,
    bytes: bytes,
    days: days,
    busiestDay: busiest,
    today: series.isEmpty ? 0 : series.last.total,
  );
}

List<ContactStat> topContacts(Iterable<MsgEvent> events, {int limit = 20, DateTime? since}) {
  final inc = <String, int>{}, out = <String, int>{}, bytes = <String, int>{};
  for (final e in events) {
    if (since != null && e.time.isBefore(since)) continue;
    final c = e.contact.isEmpty ? '(לא ידוע)' : e.contact;
    (e.outgoing ? out : inc).update(c, (v) => v + 1, ifAbsent: () => 1);
    bytes.update(c, (v) => v + e.bytes, ifAbsent: () => e.bytes);
  }
  final all = {...inc.keys, ...out.keys}
      .map((c) => ContactStat(c, inc[c] ?? 0, out[c] ?? 0, bytes[c] ?? 0))
      .toList()
    ..sort((a, b) => b.total.compareTo(a.total));
  return all.take(limit).toList();
}

/// Activity by hour of day (0-23) - shows when you message most.
List<int> hourHistogram(Iterable<MsgEvent> events, {DateTime? since}) {
  final h = List<int>.filled(24, 0);
  for (final e in events) {
    if (since != null && e.time.isBefore(since)) continue;
    h[e.time.hour]++;
  }
  return h;
}
