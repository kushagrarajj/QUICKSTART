import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/features/cart/application/cart_controller.dart';
import 'package:quickkart/features/cart/domain/cart.dart';
import 'package:quickkart/features/checkout/application/checkout_controller.dart';
import 'package:quickkart/features/orders/data/order_tracking_repository.dart';

import 'helpers/test_harness.dart';

void main() {
  late TestHarness h;

  setUp(() => h = TestHarness());
  tearDown(() => h.dispose());

  test('order history reflects a newly placed order without manual refresh',
      () async {
    expect(await h.read(ordersProvider.future), isEmpty);
    final product = h.server.product('fruits-01');
    h.read(cartControllerProvider.notifier).hydrate(Cart(lines: [
          CartLine(
            productId: product.id,
            name: product.name,
            emoji: '🍌',
            unit: '6 pcs',
            unitPricePaise: product.pricePaise,
            quantity: 1,
            maxPerOrder: product.maxPerOrder,
          ),
        ]));

    final result =
        await h.read(checkoutControllerProvider.notifier).placeOrder();

    expect(result, isA<CheckoutSuccess>());
    expect(await h.read(ordersProvider.future), hasLength(1));
  });
}
