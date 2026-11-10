import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/config_repository.dart';
import '../domain/app_config.dart';

/// The config the app is currently using. Hydrated in `main.dart` before the
/// first frame.
final appConfigControllerProvider =
    NotifierProvider<AppConfigController, AppConfig>(AppConfigController.new);

class AppConfigController extends Notifier<AppConfig> {
  @override
  AppConfig build() {
    final subscription =
        ref.read(configRepositoryProvider).remoteUpdates.listen(
      (_) => unawaited(refresh()),
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('Remote config update listener failed: $error\n$stackTrace');
      },
    );
    ref.onDispose(() => unawaited(subscription.cancel()));
    return AppConfig.defaults();
  }

  /// Used at startup with the config loaded during bootstrap.
  void hydrate(AppConfig config) => state = config;

  Future<void> refresh() async {
    state = await ref.read(configRepositoryProvider).load();
  }
}
