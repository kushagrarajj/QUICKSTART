import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/features/app_config/data/config_repository.dart';
import 'package:quickkart/features/app_config/domain/home_layout.dart';
import 'package:quickkart/features/app_config/domain/update_policy.dart';
import 'package:quickkart/features/app_config/presentation/app_config_controller.dart';

import 'helpers/test_harness.dart';

void main() {
  late TestHarness h;

  setUp(() => h = TestHarness());
  tearDown(() => h.dispose());

  test('config falls back to the last good values while offline', () async {
    final repository = h.read(configRepositoryProvider);
    final online = await repository.load();
    h.server.publishConfig({'store_open': false});
    final updated = await repository.load();
    expect(updated.storeOpen, isFalse);

    h.server.chaos.offline = true;
    final cached = await repository.load();
    expect(cached.storeOpen, isFalse);
    expect(cached.deliveryFeePaise, updated.deliveryFeePaise);
    expect(
        cached.freeDeliveryThresholdPaise, updated.freeDeliveryThresholdPaise);
    expect(online.storeOpen, isTrue);
  });

  test('config uses defaults offline when no saved values exist', () async {
    h.server.chaos.offline = true;
    final config = await h.read(configRepositoryProvider).load();
    expect(config.storeOpen, isTrue);
    expect(config.deliveryFeePaise, 2500);
  });

  test('controller refreshes on publication and cancels its listener',
      () async {
    h.read(appConfigControllerProvider);
    expect(h.server.configListenerCount, 1);

    h.server.publishConfig({'store_open': false});
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(h.read(appConfigControllerProvider).storeOpen, isFalse);

    final server = h.server;
    h.dispose();
    await Future<void>.delayed(Duration.zero);
    expect(server.configListenerCount, 0);
    h = TestHarness();
  });

  test('parses versions numerically and rejects malformed config versions', () {
    expect(
      UpdatePolicy.evaluate(
        currentVersion: '1.9.9',
        minSupportedVersion: '1.10.0',
        latestVersion: '2.0',
      ),
      UpdateRequirement.required,
    );
    expect(
      UpdatePolicy.evaluate(
        currentVersion: '1.4',
        minSupportedVersion: '1.4.0',
        latestVersion: '1.5.0',
      ),
      UpdateRequirement.optional,
    );
    expect(
      UpdatePolicy.evaluate(
        currentVersion: '1.x',
        minSupportedVersion: '2.0',
        latestVersion: '3.0',
      ),
      UpdateRequirement.none,
    );
  });

  test('home layout preserves known order and ignores unknown duplicates', () {
    expect(
      HomeLayout.parse(jsonEncode([
        'deals',
        'banner',
        'video',
        'deals',
        'all_products',
      ])),
      [
        HomeSection.deals,
        HomeSection.banner,
        HomeSection.allProducts,
      ],
    );
    expect(HomeLayout.parse('[broken,'), HomeLayout.defaultSections);
    expect(HomeLayout.parse('["unknown"]'), HomeLayout.defaultSections);
  });
}
