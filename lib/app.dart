import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'core/providers.dart';
import 'features/app_config/domain/app_config.dart';
import 'features/app_config/domain/update_policy.dart';
import 'features/app_config/presentation/app_config_controller.dart';
import 'features/catalog/presentation/home_screen.dart';

class QuickKartApp extends StatelessWidget {
  const QuickKartApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'QuickKart',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF0C831F),
        scaffoldBackgroundColor: const Color(0xFFF6F7F9),
      ),
      home: const _UpdateGate(),
    );
  }
}

class _UpdateGate extends ConsumerStatefulWidget {
  const _UpdateGate();

  @override
  ConsumerState<_UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends ConsumerState<_UpdateGate> {
  final Set<String> _handledOptionalVersions = {};
  String? _promptingVersion;

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(appConfigControllerProvider);
    final requirement = UpdatePolicy.evaluate(
      currentVersion: ref.watch(appVersionProvider),
      minSupportedVersion: config.minSupportedVersion,
      latestVersion: config.latestVersion,
    );
    if (requirement == UpdateRequirement.required) {
      return _RequiredUpdateScreen(config: config);
    }
    if (requirement == UpdateRequirement.optional) {
      _scheduleOptionalPrompt(config);
    }
    return const HomeScreen();
  }

  void _scheduleOptionalPrompt(AppConfig config) {
    final version = config.latestVersion;
    if (_handledOptionalVersions.contains(version) ||
        _promptingVersion == version) {
      return;
    }
    _promptingVersion = version;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_showOptionalPrompt(config));
    });
  }

  Future<void> _showOptionalPrompt(AppConfig config) async {
    final version = config.latestVersion;
    final key = 'update.optional.dismissed.$version';
    try {
      if (await ref.read(keyValueStoreProvider).getString(key) == 'true') {
        _handledOptionalVersions.add(version);
        _promptingVersion = null;
        return;
      }
    } on Object catch (error, stackTrace) {
      debugPrint(
          'Could not read optional update preference: $error\n$stackTrace');
    }
    if (!mounted ||
        UpdatePolicy.evaluate(
              currentVersion: ref.read(appVersionProvider),
              minSupportedVersion: config.minSupportedVersion,
              latestVersion:
                  ref.read(appConfigControllerProvider).latestVersion,
            ) !=
            UpdateRequirement.optional) {
      _promptingVersion = null;
      return;
    }

    final updateNow = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        title: const Text('An update is available'),
        content: Text('Version ${config.latestVersion} is ready to install.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Update'),
          ),
        ],
      ),
    );
    _handledOptionalVersions.add(version);
    _promptingVersion = null;
    if (!mounted) return;
    if (updateNow == true) {
      await _openUpdateUrl(config.updateUrl);
      return;
    }
    try {
      await ref.read(keyValueStoreProvider).setString(key, 'true');
    } on Object catch (error, stackTrace) {
      debugPrint(
          'Could not save optional update preference: $error\n$stackTrace');
    }
  }

  Future<void> _openUpdateUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !uri.hasScheme ||
        (uri.scheme != 'https' && uri.scheme != 'http')) {
      _showUpdateError('The update link is not valid.');
      return;
    }
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        _showUpdateError('Could not open the update link.');
      }
    } on Object catch (error, stackTrace) {
      debugPrint('Could not open update link: $error\n$stackTrace');
      _showUpdateError('Could not open the update link.');
    }
  }

  void _showUpdateError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

class _RequiredUpdateScreen extends StatelessWidget {
  const _RequiredUpdateScreen({required this.config});

  final AppConfig config;

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        child: Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.system_update_alt, size: 56),
                    const SizedBox(height: 16),
                    Text('Update required',
                        style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 8),
                    Text(
                      'This version is no longer supported. Update to '
                      '${config.latestVersion} to continue.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: () async {
                        final uri = Uri.tryParse(config.updateUrl);
                        if (uri == null ||
                            !uri.hasScheme ||
                            (uri.scheme != 'https' && uri.scheme != 'http')) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('The update link is not valid.')),
                          );
                          return;
                        }
                        try {
                          if (!await launchUrl(
                            uri,
                            mode: LaunchMode.externalApplication,
                          )) {
                            throw StateError('The update link could not open');
                          }
                        } on Object catch (error, stackTrace) {
                          debugPrint('Could not open update link: '
                              '$error\n$stackTrace');
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content:
                                      Text('Could not open the update link.')),
                            );
                          }
                        }
                      },
                      child: const Text('Update now'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}
