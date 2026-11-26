/// Small English formatting helpers, so we don't need the intl package.
library;

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Currency used by [formatMoney]: 'CHF' or 'EUR'. Set from the settings
/// by the store.
String moneyCurrency = 'CHF';

const supportedCurrencies = ['CHF', 'EUR'];

/// `24850` → `24,850`
String formatAmount(num value) {
  final digits = value.abs().round().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return '${value < 0 ? '-' : ''}$buffer';
}

/// `24850` → `CHF 24,850` (or `€24,850`)
String formatMoney(num value) => moneyCurrency == 'EUR'
    ? '€${formatAmount(value)}'
    : 'CHF ${formatAmount(value)}';

/// `0.324` → `32.4%`
String formatPercent(double fraction) =>
    '${(fraction * 100).toStringAsFixed(1)}%';

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

String _two(int n) => n.toString().padLeft(2, '0');

String formatTime(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';

/// `Today`, `Yesterday`, `Tomorrow`, or `Nov 20` (plus year if not current).
String formatDay(DateTime d, DateTime now) {
  final diff = dateOnly(d).difference(dateOnly(now)).inDays;
  if (diff == 0) return 'Today';
  if (diff == -1) return 'Yesterday';
  if (diff == 1) return 'Tomorrow';
  final base = '${_months[d.month - 1]} ${d.day}';
  return d.year == now.year ? base : '$base, ${d.year}';
}

/// `Nov 24, 2026`
String formatDate(DateTime d) => '${_months[d.month - 1]} ${d.day}, ${d.year}';

/// `Today · 11:30`
String formatDayTime(DateTime d, DateTime now) =>
    '${formatDay(d, now)} · ${formatTime(d)}';

/// Short relative time for activity feeds: `now`, `10m`, `3h`, `2d`.
String formatAgo(DateTime d, DateTime now) {
  final diff = now.difference(d);
  if (diff.inMinutes < 1) return 'now';
  if (diff.inHours < 1) return '${diff.inMinutes}m';
  if (diff.inDays < 1) return '${diff.inHours}h';
  if (diff.inDays < 7) return '${diff.inDays}d';
  return formatDay(d, now);
}

String initialsOf(String name) => name
    .split(' ')
    .where((part) => part.isNotEmpty)
    .take(2)
    .map((part) => part[0])
    .join()
    .toUpperCase();

/// Parses `4,500`, `4500`, `4500.50`, `CHF 4'500`, `€4,500` → 4500 / 4500.5
double? parseMoney(String input) {
  final cleaned = input
      .replaceAll(RegExp('chf|eur|€|fr\\.?', caseSensitive: false), '')
      .replaceAll(RegExp(r"[\s,']"), '');
  if (cleaned.isEmpty) return null;
  return double.tryParse(cleaned);
}
