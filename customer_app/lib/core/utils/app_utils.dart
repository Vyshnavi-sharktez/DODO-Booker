class AppUtils {
  AppUtils._();

  static bool isValidPhone(String phone) {
    return RegExp(r'^\+?[0-9]{10,13}$').hasMatch(phone);
  }

  static bool isValidEmail(String email) {
    return RegExp(r'^[\w-.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email);
  }

  static String formatCurrency(double amount) {
    return '₹${amount.toStringAsFixed(2)}';
  }
}
