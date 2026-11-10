/// Money helpers.
///
/// Every amount inside the app is an integer number of **paise**
/// (1 rupee = 100 paise). Never store money in a `double`.
library;

/// Formats paise for display.
String formatMoney(int paise) {
  final rupees = paise ~/ 100;
  final remainder = paise.abs() % 100;
  return remainder == 0
      ? '₹$rupees'
      : '₹$rupees.${remainder.toString().padLeft(2, '0')}';
}

/// Converts a rupee amount coming from the (legacy) API into paise.
int rupeesToPaise(num rupees) => (rupees * 100).round();
