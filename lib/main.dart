import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fridgie_app/app/app.dart';
import 'package:fridgie_app/app/settings_controller.dart';
import 'package:fridgie_app/app/theme/app_theme.dart';
import 'package:fridgie_app/app/providers.dart';
import 'package:fridgie_app/core/db/app_database.dart';
import 'package:fridgie_app/features/backup/data/backup_service.dart';
import 'package:fridgie_app/features/notifications/data/notification_service.dart';
import 'package:openfoodfacts/openfoodfacts.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  OpenFoodAPIConfiguration.userAgent = UserAgent(
    name: 'Fridgie',
    version: '0.2.16',
    url: 'https://github.com/openfoodfacts/openfoodfacts-dart',
    comment: 'fridgie-app',
  );
  await EasyLocalization.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.manual,
    overlays: <SystemUiOverlay>[
      SystemUiOverlay.top,
      SystemUiOverlay.bottom,
    ],
  );
  await BackupService.applyPendingRestoreIfExists();
  final SettingsState initialSettings = await _loadInitialSettings();
  runApp(
    EasyLocalization(
      supportedLocales: const <Locale>[Locale('en'), Locale('uk'), Locale('ru')],
      path: 'assets/l10n',
      fallbackLocale: const Locale('en'),
      startLocale: Locale(initialSettings.localeCode),
      child: ProviderScope(
        overrides: <Override>[
          settingsControllerProvider.overrideWith(
            (Ref ref) => SettingsController(
              ref.read(dbProvider),
              initialState: initialSettings,
            ),
          ),
        ],
        child: const FridgieApp(),
      ),
    ),
  );

  WidgetsBinding.instance.addPostFrameCallback((_) {
    // Defer non-critical prompts to keep route transitions smooth right after startup.
    Future<void>.delayed(const Duration(milliseconds: 700), () async {
      try {
        await <Permission>[
          Permission.ignoreBatteryOptimizations,
          Permission.camera,
          Permission.audio,
          Permission.photos,
          Permission.videos,
          Permission.storage,
        ].request();
      } catch (_) {}
    });

    // Initialize notifications later to avoid competing with first interactions.
    Future<void>.delayed(const Duration(milliseconds: 1200), () async {
      try {
        await NotificationService(notificationsPlugin).initialize();
      } catch (e) {
        // ignore: avoid_print
        print('Deferred notification init failed: $e');
      }
    });
  });
}

Future<SettingsState> _loadInitialSettings() async {
  final AppDatabase db = AppDatabase();
  try {
    final List<AppSetting> rows = await db.select(db.appSettings).get();
    final Map<String, String> map = <String, String>{
      for (final AppSetting row in rows) row.key: row.value,
    };

    final ThemeMode themeMode = switch (map['ui_theme_mode']) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    final AppAccent accent = accentFromString(map['ui_accent'] ?? 'teal');
    final String localeCode = switch (map['ui_locale']) {
      'uk' => 'uk',
      'ru' => 'ru',
      _ => 'en',
    };

    return SettingsState(
      themeMode: themeMode,
      accent: accent,
      localeCode: localeCode,
    );
  } catch (_) {
    return const SettingsState(
      themeMode: ThemeMode.system,
      accent: AppAccent.teal,
      localeCode: 'en',
    );
  } finally {
    await db.close();
  }
}
