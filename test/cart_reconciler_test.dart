import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/core/network/api_exceptions.dart';
import 'package:quickkart/features/cart/application/cart_reconciler.dart';
import 'package:quickkart/features/cart/domain/cart.dart';

import 'helpers/test_harness.dart';

void main() {
  late TestHarness h;

  setUp(() => h = TestHarness());
  tearDown(() => h.dispose());

  CartLine line(String id, int quantity) => CartLine(
        productId: id,
        name: id,
        emoji: '🛒',
        unit: 'each',
        unitPricePaise: h.server.product(id).pricePaise,
        quantity: quantity,
        maxPerOrder: 10,
      );

  test('reconciles all conflicts while preserving remaining line order',
      () async {
    final cart = Cart(lines: [
      line('fruits-00', 1),
      line('fruits-01', 2),
      line('fruits-02', 3),
      line('fruits-03', 1),
    ]);
    h.server.simulateCartConflicts(cart.lines.map((l) => l.productId).toList());

    final result = await h.read(cartReconcilerProvider).reconcile(cart);

    expect(
        result.cart.lines.map((l) => l.productId), ['fruits-00', 'fruits-02']);
    expect(result.cart.lines.first.unitPricePaise,
        h.server.product('fruits-00').pricePaise);
    expect(result.cart.lines.last.quantity, 1);
    expect(result.cart.lines.last.maxPerOrder, 1);
    expect(result.changes, hasLength(4));
    expect(result.requiresUserReview, isTrue);
  });

  test('fails without returning a partial cart when the server is offline',
      () async {
    final cart = Cart(lines: [line('fruits-00', 1)]);
    h.server
        .setPrice('fruits-00', h.server.product('fruits-00').pricePaise + 100);
    h.server.chaos.offline = true;

    await expectLater(
      h.read(cartReconcilerProvider).reconcile(cart),
      throwsA(isA<NetworkException>()),
    );
  });
}
