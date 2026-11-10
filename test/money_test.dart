import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/core/utils/money.dart';

void main() {
  test('formats paise only when present', () {
    expect(formatMoney(5000), '₹50');
    expect(formatMoney(4999), '₹49.99');
    expect(formatMoney(5), '₹0.05');
  });

  test('converts decimal rupees to paise without truncating', () {
    expect(rupeesToPaise(19.99), 1999);
    expect(rupeesToPaise(50), 5000);
  });
}
