import 'package:intl/intl.dart';

String formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  double v = bytes.toDouble();
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  // Wrapped in direction marks so "537 MB" never gets reordered inside Hebrew text.
  return '\u200e${v.toStringAsFixed(v >= 100 || i == 0 ? 0 : 1)} ${units[i]}\u200f';
}

final _num = NumberFormat.decimalPattern('he');
String formatCount(num n) => _num.format(n);

String formatDay(DateTime d) => DateFormat('d/M').format(d);
String formatDate(DateTime d) => DateFormat('d/M/yy').format(d);
