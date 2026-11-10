import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/providers.dart';
import '../../../core/storage/key_value_store.dart';
import '../domain/app_config.dart';

final configRepositoryProvider = Provider<ConfigRepository>(
  (ref) => ConfigRepository(
    ref.watch(apiClientProvider),
    ref.watch(keyValueStoreProvider),
    remoteUpdates: () => ref.read(mockServerProvider).configUpdates,
  ),
);

/// Loads remote config (think: Firebase Remote Config).
class ConfigRepository {
  ConfigRepository(
    this._client,
    this._store, {
    required Stream<int> Function() remoteUpdates,
  }) : _remoteUpdates = remoteUpdates;

  final ApiClient _client;
  final KeyValueStore _store;
  final Stream<int> Function() _remoteUpdates;

  static const _cacheKey = 'app_config.last_known_good.v1';

  /// Fires (with the new config version) every time config is published
  /// from the console. Equivalent to Firebase's `onConfigUpdated`.
  Stream<int> get remoteUpdates => _remoteUpdates();

  /// Fetches the latest config.
  Future<AppConfig> load() async {
    try {
      final response = await _client.get('/v1/config', forceRefresh: true);
      if (response is! Map<String, dynamic> || response['values'] is! Map) {
        throw const FormatException('Remote config response is malformed');
      }
      final rawValues = response['values'] as Map;
      final values = <String, Object?>{};
      for (final entry in rawValues.entries) {
        if (entry.key is! String) {
          throw const FormatException('Remote config keys must be strings');
        }
        values[entry.key as String] = entry.value;
      }
      final config = AppConfig.fromValues(values);
      try {
        await _store.setString(_cacheKey, jsonEncode(config.toValues()));
      } on Object catch (error, stackTrace) {
        debugPrint('Could not cache remote config: $error\n$stackTrace');
      }
      return config;
    } on Object catch (error, stackTrace) {
      debugPrint('Could not load remote config: $error\n$stackTrace');
      return _loadCachedOrDefaults();
    }
  }

  Future<AppConfig> _loadCachedOrDefaults() async {
    try {
      final raw = await _store.getString(_cacheKey);
      if (raw == null) return AppConfig.defaults();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        throw const FormatException('Cached config is malformed');
      }
      final values = <String, Object?>{};
      for (final entry in decoded.entries) {
        if (entry.key is! String) {
          throw const FormatException('Cached config keys must be strings');
        }
        values[entry.key as String] = entry.value;
      }
      return AppConfig.fromValues(values);
    } on Object catch (error, stackTrace) {
      debugPrint('Could not read cached config: $error\n$stackTrace');
      return AppConfig.defaults();
    }
  }
}
