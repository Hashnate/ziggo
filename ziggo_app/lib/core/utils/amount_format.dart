import 'package:intl/intl.dart';

/// Amounts and counts with a comma every three digits: 200000 -> "200,000",
/// formatAmount(1234.5, 2) -> "1,234.50". Takes a num, a numeric string or null
/// (shown as 0); anything else is returned unchanged.
String formatAmount(Object? value, [int decimals = 0]) {
  final n = value is num ? value : num.tryParse(value?.toString() ?? '0');
  if (n == null) return value.toString();
  final pattern = decimals > 0 ? '#,##0.${'0' * decimals}' : '#,##0';
  return NumberFormat(pattern, 'en_US').format(n);
}
