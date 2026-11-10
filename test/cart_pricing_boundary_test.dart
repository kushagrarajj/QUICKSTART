import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/features/app_config/domain/app_config.dart';
import 'package:quickkart/features/cart/domain/cart.dart';
import 'package:quickkart/features/cart/domain/cart_pricing.dart';

void main() {
  test('free delivery applies at the exact threshold', () {
    const cart = Cart(lines: [
      CartLine(
        productId: 'tomato',
        name: 'Tomato',
        emoji: '🍅',
        unit: '500 g',
        unitPricePaise: 19900,
        quantity: 1,
        maxPerOrder: 1,
      ),
    ]);

    final pricing = CartPricing.compute(cart, AppConfig.defaults());

    expect(pricing.deliveryFeePaise, 0);
    expect(pricing.totalPaise, 19900);
  });
}
