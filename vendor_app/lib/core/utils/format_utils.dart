import 'package:intl/intl.dart';

abstract final class FormatUtils {
  static final _currency = NumberFormat.currency(
    symbol: '₹',
    decimalDigits: 2,
    locale: 'en_IN',
  );

  static String currency(double amount) => _currency.format(amount);

  static String compact(double amount) =>
      NumberFormat.compact(locale: 'en_IN').format(amount);

  static String capitalize(String value) =>
      value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';

  static String bookingStatusLabel(String status) {
    return status.replaceAll('_', ' ').split(' ').map(capitalize).join(' ');
  }

  static String initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
}
