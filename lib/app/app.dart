import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fridgie_app/app/providers.dart';
import 'package:fridgie_app/app/settings_controller.dart';
import 'package:fridgie_app/app/theme/app_theme.dart';
import 'package:fridgie_app/app/router.dart';

class FridgieApp extends ConsumerWidget {
  const FridgieApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<SettingsState> settingsAsync =
        ref.watch(settingsControllerProvider);
    final SettingsState settings = settingsAsync.value ??
        const SettingsState(
          themeMode: ThemeMode.system,
          accent: AppAccent.teal,
          localeCode: 'en',
        );

    return MaterialApp.router(
      title: 'Fridgie',
      debugShowCheckedModeBanner: false,
      routerConfig: appRouter,
      themeMode: settings.themeMode,
      theme: buildAppTheme(
        brightness: ThemeBrightness.light,
        accent: settings.accent,
      ),
      darkTheme: buildAppTheme(
        brightness: ThemeBrightness.dark,
        accent: settings.accent,
      ),
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: Locale(settings.localeCode),
    );
  }
}
