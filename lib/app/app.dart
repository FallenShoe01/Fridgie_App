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

      themeAnimationDuration: const Duration(milliseconds: 280),
      themeAnimationCurve: Curves.easeOutCubic,
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
      // Let EasyLocalization drive the active `Locale` (via `context.locale`).
      // When settings change, sync EasyLocalization to the stored value so
      // the app updates immediately and persistently.
      locale: context.locale,
      builder: (BuildContext ctx, Widget? child) {
        // Ensure EasyLocalization reflects persisted settings once loaded.
        if (settingsAsync is AsyncData<SettingsState>) {
          final Locale target = Locale(settings.localeCode);
          if (ctx.locale.languageCode != target.languageCode) {
            // Fire-and-forget: caller of setLocale will rebuild app when done.
            // Use addPostFrameCallback to avoid changing locale during build.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              ctx.setLocale(target);
            });
          }
        }

        if (child == null) return const SizedBox.shrink();
        final MediaQueryData media = MediaQuery.of(ctx);
        final double width = media.size.width;
        final double widthFactor = width < 360
            ? 0.90
            : width < 400
                ? 0.95
                : 1.0;
        final double baseScale = media.textScaler.scale(1.0);
        final double responsiveScale =
            (baseScale * widthFactor).clamp(0.85, 2.0);

        final Widget content = MediaQuery(
          data: media.copyWith(
            textScaler: TextScaler.linear(responsiveScale),
          ),
          child: SafeArea(left: false, right: false, child: child),
        );

        return content;
      },
    );
  }
}
