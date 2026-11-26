import 'package:intl/intl.dart';

String formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  double v = bytes.toDouble();
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(v >= 100 || i == 0 ? 0 : 1)} ${units[i]}';
}

final _num = NumberFormat.decimalPattern('he');
String formatCount(num n) => _num.format(n);

String formatDay(DateTime d) => DateFormat('d/M').format(d);
String formatDate(DateTime d) => DateFormat('d/M/yy').format(d);
