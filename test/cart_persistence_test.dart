import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/features/cart/application/cart_controller.dart';
import 'package:quickkart/features/cart/data/cart_storage.dart';
import 'package:quickkart/features/cart/domain/cart.dart';
import 'package:quickkart/features/cart/domain/coupon.dart';

import 'helpers/test_harness.dart';

void main() {
  late TestHarness h;

  setUp(() => h = TestHarness());
  tearDown(() => h.dispose());

  Cart cart() => Cart(
        lines: const [
          CartLine(
            productId: 'snacks-00',
            name: 'Chips',
            emoji: '🥔',
            unit: '52 g',
            unitPricePaise: 2000,
            quantity: 2,
            maxPerOrder: 10,
          ),
        ],
        coupon: Coupon(
          code: 'FLAT50',
          type: CouponType.flat,
          value: 5000,
          minOrderPaise: 0,
          expiresAt: DateTime.utc(2099),
        ),
      );

  test('decrement is persisted and survives restart', () async {
    await h.read(cartStorageProvider).save(cart());
    final controller = h.read(cartControllerProvider.notifier);
    controller.hydrate(cart());

    await controller.decrement('snacks-00');

    final restored = await h
        .read(
          // Cart storage is obtained through the harness to exercise persistence.
          // The same store is reused by restart().
          cartStorageProvider,
        )
        .load();
    expect(restored.quantityOf('snacks-00'), 1);
    final restarted = h.restart();
    expect(await restarted.read(cartStorageProvider).load(), restored);
    restarted.dispose();
  });

  test('rapid increments are serialized and all persist', () async {
    final initial = cart().updateQuantity('snacks-00', 1);
    await h.read(cartStorageProvider).save(initial);
    final controller = h.read(cartControllerProvider.notifier);
    controller.hydrate(initial);

    await Future.wait([
      controller.increment('snacks-00'),
      controller.increment('snacks-00'),
      controller.increment('snacks-00'),
    ]);

    expect(h.read(cartControllerProvider).quantityOf('snacks-00'), 4);
    expect(
      (await h.read(cartStorageProvider).load()).quantityOf('snacks-00'),
      4,
    );
  });

  test('remove is persisted and survives restart', () async {
    await h.read(cartStorageProvider).save(cart());
    final controller = h.read(cartControllerProvider.notifier);
    controller.hydrate(cart());

    await controller.remove('snacks-00');

    final restored = await h.read(cartStorageProvider).load();
    expect(restored.lines, isEmpty);
    final restarted = h.restart();
    expect(await restarted.read(cartStorageProvider).load(), restored);
    restarted.dispose();
  });

  test('removing a coupon is persisted and survives restart', () async {
    await h.read(cartStorageProvider).save(cart());
    final controller = h.read(cartControllerProvider.notifier);
    controller.hydrate(cart());

    await controller.removeCoupon();

    final restored = await h.read(cartStorageProvider).load();
    expect(restored.coupon, isNull);
    final restarted = h.restart();
    expect(await restarted.read(cartStorageProvider).load(), restored);
    restarted.dispose();
  });
}
