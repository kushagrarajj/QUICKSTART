import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/features/app_config/data/config_repository.dart';
import 'package:quickkart/features/app_config/presentation/app_config_controller.dart';
import 'package:quickkart/features/cart/application/cart_controller.dart';
import 'package:quickkart/features/cart/domain/cart.dart';
import 'package:quickkart/features/checkout/application/checkout_controller.dart';

import 'helpers/test_harness.dart';

void main() {
  late TestHarness h;

  setUp(() => h = TestHarness());
  tearDown(() => h.dispose());

  Cart cart() {
    final product = h.server.product('fruits-01');
    return Cart(lines: [
      CartLine(
        productId: product.id,
        name: product.name,
        emoji: '🍌',
        unit: '6 pcs',
        unitPricePaise: product.pricePaise,
        quantity: 1,
        maxPerOrder: product.maxPerOrder,
      ),
    ]);
  }

  void hydrateCart() => h.read(cartControllerProvider.notifier).hydrate(cart());

  test('lost order response retries with the same idempotency key', () async {
    hydrateCart();
    h.server.chaos.loseNextOrderResponses = 1;

    final result =
        await h.read(checkoutControllerProvider.notifier).placeOrder();

    expect(result, isA<CheckoutSuccess>());
    expect(h.server.orderCount, 1);
    final requests = h.server.requestLog
        .where((request) =>
            request.method == 'POST' && request.path == '/v1/orders')
        .toList();
    expect(requests, hasLength(2));
    final keys = requests.map((r) => r.headers['Idempotency-Key']).toSet();
    expect(keys, hasLength(1));
    expect(keys.single, isNotNull);
  });

  test('a later retry after two lost responses still creates one order',
      () async {
    hydrateCart();
    h.server.chaos.loseNextOrderResponses = 2;
    final controller = h.read(checkoutControllerProvider.notifier);

    final uncertain = await controller.placeOrder();

    expect(uncertain, isA<CheckoutFailure>());
    expect((uncertain as CheckoutFailure).message,
        contains('may have been placed'));
    expect(h.server.orderCount, 1);
    final restarted = h.restart();
    restarted.read(cartControllerProvider.notifier).hydrate(cart());

    final recovered =
        await restarted.read(checkoutControllerProvider.notifier).placeOrder();

    expect(recovered, isA<CheckoutSuccess>());
    expect(h.server.orderCount, 1);
    restarted.dispose();
  });

  test('concurrent placeOrder calls share one in-flight request', () async {
    hydrateCart();
    h.server.chaos.latencyOverride = (request) => request.path == '/v1/orders'
        ? const Duration(milliseconds: 25)
        : Duration.zero;
    final controller = h.read(checkoutControllerProvider.notifier);

    final results = await Future.wait([
      controller.placeOrder(),
      controller.placeOrder(),
    ]);

    expect(results, everyElement(isA<CheckoutSuccess>()));
    expect(h.server.orderCount, 1);
    expect(
      h.server.requestLog.where(
        (r) => r.method == 'POST' && r.path == '/v1/orders',
      ),
      hasLength(1),
    );
  });

  test('price conflict updates cart and requires review before ordering',
      () async {
    hydrateCart();
    h.server.simulateCartConflicts(['fruits-01']);

    final result =
        await h.read(checkoutControllerProvider.notifier).placeOrder();

    expect(result, isA<CheckoutNeedsReview>());
    expect(h.server.orderCount, 0);
    expect(h.read(cartControllerProvider).lines.single.unitPricePaise,
        h.server.product('fruits-01').pricePaise);
  });

  test('known closed store blocks checkout before the order request', () async {
    h.server.publishConfig({'store_open': false});
    final config = await h.read(configRepositoryProvider).load();
    h.read(appConfigControllerProvider.notifier).hydrate(config);
    hydrateCart();
    h.server.requestLog.clear();

    final result =
        await h.read(checkoutControllerProvider.notifier).placeOrder();

    expect(result, isA<CheckoutFailure>());
    expect(h.server.orderCount, 0);
    expect(h.server.requestLog.where((r) => r.path == '/v1/orders'), isEmpty);
  });
}
