/// Human friendly formatting helpers (Turkish UI).
library;

String formatBytes(num bytes, {int decimals = 1}) {
  if (bytes < 1024) return '${bytes.toInt()} B';
  const units = ['KB', 'MB', 'GB', 'TB', 'PB'];
  double value = bytes / 1024;
  var i = 0;
  while (value >= 1024 && i < units.length - 1) {
    value /= 1024;
    i++;
  }
  final d = value >= 100 ? 0 : decimals;
  return '${value.toStringAsFixed(d).replaceAll('.', ',')} ${units[i]}';
}

String formatSpeed(num bytesPerSecond) {
  if (bytesPerSecond <= 0) return '—';
  return '${formatBytes(bytesPerSecond)}/sn';
}

String formatDuration(Duration d) {
  if (d.isNegative) return '—';
  final s = d.inSeconds;
  if (s < 1) return '<1 sn';
  if (s < 60) return '$s sn';
  final m = d.inMinutes;
  if (m < 60) return '$m dk ${s % 60} sn';
  final h = d.inHours;
  if (h < 24) return '$h sa ${m % 60} dk';
  return '${d.inDays} gün ${h % 24} sa';
}

String formatEta(int remainingBytes, double speed) {
  if (speed <= 1) return 'hesaplanıyor…';
  return formatDuration(Duration(milliseconds: (remainingBytes / speed * 1000).round()));
}

const _months = [
  'Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz',
  'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara',
];

String two(int v) => v.toString().padLeft(2, '0');

String formatClock(DateTime t) => '${two(t.hour)}:${two(t.minute)}';

String formatDate(DateTime t) => '${t.day} ${_months[t.month - 1]} ${t.year}';

String formatDateTime(DateTime t) => '${formatDate(t)}, ${formatClock(t)}';

/// "az önce", "5 dk önce", "dün 14:20", "3 Kas 2026"
String formatRelative(DateTime t, {DateTime? now}) {
  now ??= DateTime.now();
  final diff = now.difference(t);
  if (diff.inSeconds < 45) return 'az önce';
  if (diff.inMinutes < 60) return '${diff.inMinutes} dk önce';
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(t.year, t.month, t.day);
  final days = today.difference(day).inDays;
  if (days == 0) return 'bugün ${formatClock(t)}';
  if (days == 1) return 'dün ${formatClock(t)}';
  if (days < 7) return '$days gün önce';
  return formatDate(t);
}

/// Group header label used by the history page.
String dayGroupLabel(DateTime t, {DateTime? now}) {
  now ??= DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(t.year, t.month, t.day);
  final days = today.difference(day).inDays;
  if (days == 0) return 'Bugün';
  if (days == 1) return 'Dün';
  if (days < 7) return 'Bu hafta';
  return '${_monthLong[t.month - 1]} ${t.year}';
}

const _monthLong = [
  'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran',
  'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık',
];

String plural(int n, String word) => '$n $word';
