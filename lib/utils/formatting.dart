import 'package:intl/intl.dart';

final _currency = NumberFormat.simpleCurrency();
final _compactCurrency = NumberFormat.compactSimpleCurrency();
final _shortDate = DateFormat.MMMd();
final _longDate = DateFormat('d MMM yyyy');
final _monthLabel = DateFormat.MMM();

String formatCurrency(num amount) => _currency.format(amount);

/// Abbreviated for chart axes: $250, $1K, $1.5K, $10K.
String formatCompactCurrency(num amount) => _compactCurrency.format(amount);

String formatMonthLabel(DateTime date) => _monthLabel.format(date);

String formatShortDate(DateTime date) => _shortDate.format(date);

String formatLongDate(DateTime date) => _longDate.format(date);

String formatDelta(double? delta) {
  if (delta == null) return '—';
  final arrow = delta >= 0 ? '▲' : '▼';
  return '$arrow ${_currency.format(delta.abs())}';
}

String formatRelativeDays(DateTime date, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final diff = today.difference(date).inDays;
  if (diff <= 0) return 'today';
  if (diff == 1) return '1d ago';
  return '${diff}d ago';
}
