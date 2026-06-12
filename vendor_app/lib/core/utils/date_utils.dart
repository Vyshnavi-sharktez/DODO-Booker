import 'package:intl/intl.dart';

abstract final class AppDateUtils {
  static String formatDisplay(DateTime date) =>
      DateFormat('dd MMM yyyy').format(date);

  static String formatWithTime(DateTime date) =>
      DateFormat('dd MMM yyyy, hh:mm a').format(date);

  static String formatTimeOnly(DateTime date) =>
      DateFormat('hh:mm a').format(date);

  static String formatIsoDate(DateTime date) =>
      date.toIso8601String().substring(0, 10);

  static String relativeLabel(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    return formatDisplay(date);
  }
}
