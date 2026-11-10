import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/features/catalog/data/catalog_repository.dart';

import 'helpers/test_harness.dart';

void main() {
  late TestHarness h;

  setUp(() => h = TestHarness());
  tearDown(() => h.dispose());

  test('offline fallback is isolated by category', () async {
    final repository = h.read(catalogRepositoryProvider);
    final fruits = await repository.getPage(categoryId: 'fruits');
    await repository.getPage(categoryId: 'dairy');

    h.server.chaos.offline = true;
    final offlineFruits = await repository.getPage(categoryId: 'fruits');

    expect(offlineFruits.fromCache, isTrue);
    expect(offlineFruits.items.map((p) => p.id), fruits.items.map((p) => p.id));
  });

  test('catalog refresh fetches updated server prices', () async {
    final repository = h.read(catalogRepositoryProvider);
    final first = await repository.getPage(categoryId: 'fruits');
    final original =
        first.items.firstWhere((product) => product.id == 'fruits-00');
    h.server.setPrice(original.id, original.pricePaise + 100);

    final refreshed = await repository.getPage(categoryId: 'fruits');
    final updated =
        refreshed.items.firstWhere((product) => product.id == original.id);

    expect(updated.pricePaise, original.pricePaise + 100);
  });

  test('deals previously loaded remain available offline', () async {
    final online = await h.read(catalogRepositoryProvider).getDeals();
    expect(online.items, isNotEmpty);
    h.server.chaos.offline = true;

    final offline = await h.read(catalogRepositoryProvider).getDeals();

    expect(offline.fromCache, isTrue);
    expect(offline.items, online.items);
  });
}
