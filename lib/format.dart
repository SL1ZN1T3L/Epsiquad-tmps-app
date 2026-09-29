import 'package:intl/intl.dart';

const _units = ['Б', 'КБ', 'МБ', 'ГБ', 'ТБ'];

String fmtSize(int bytes) {
  if (bytes <= 0) return '0 Б';
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < _units.length - 1) {
    value /= 1024;
    unit++;
  }
  final text = value >= 100 || unit == 0
      ? value.round().toString()
      : value.toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '');
  return '$text ${_units[unit]}';
}

String plural(int n, String one, String few, String many) {
  final m10 = n % 10;
  final m100 = n % 100;
  if (m10 == 1 && m100 != 11) return one;
  if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return few;
  return many;
}

String fmtHours(int hours) {
  if (hours > 0 && hours % 24 == 0) {
    final days = hours ~/ 24;
    return '$days ${plural(days, 'день', 'дня', 'дней')}';
  }
  return '$hours ч';
}

String fmtLeft(Duration left) {
  if (left.inSeconds <= 0) return 'истекло';
  final days = left.inDays;
  final hours = left.inHours % 24;
  final minutes = left.inMinutes % 60;
  if (days > 0) return '$days ${plural(days, 'день', 'дня', 'дней')} $hours ч';
  if (hours > 0) return '$hours ч $minutes мин';
  if (minutes > 0) return '$minutes мин';
  return 'меньше минуты';
}

final _dateFormat = DateFormat('d MMM, HH:mm', 'ru');
final _dayFormat = DateFormat('d MMMM y', 'ru');

String fmtDate(DateTime? at) => at == null ? 'бессрочно' : _dateFormat.format(at.toLocal());

String fmtDay(DateTime? at) => at == null ? '-' : _dayFormat.format(at.toLocal());

String fmtRelative(DateTime at) {
  final diff = DateTime.now().difference(at.toLocal());
  if (diff.inSeconds < 60) return 'только что';
  if (diff.inMinutes < 60) return '${diff.inMinutes} мин назад';
  if (diff.inHours < 24) return '${diff.inHours} ч назад';
  return fmtDate(at);
}

String fmtSpeed(int bytesPerSecond) => '${fmtSize(bytesPerSecond)}/с';
