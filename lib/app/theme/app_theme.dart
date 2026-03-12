import 'package:flutter/material.dart';

enum AppAccent {
  teal,
  blue,
  orange,
  green,
}

Color accentToSeed(AppAccent accent) {
  return switch (accent) {
    AppAccent.teal => Colors.teal,
    AppAccent.blue => Colors.blue,
    AppAccent.orange => Colors.deepOrange,
    AppAccent.green => Colors.green,
  };
}

AppAccent accentFromString(String raw) {
  return AppAccent.values.firstWhere(
    (AppAccent value) => value.name == raw,
    orElse: () => AppAccent.teal,
  );
}

ThemeData buildAppTheme({
  required ThemeBrightness brightness,
  required AppAccent accent,
}) {
  final Color seed = accentToSeed(accent);
  final Brightness mode = switch (brightness) {
    ThemeBrightness.light => Brightness.light,
    ThemeBrightness.dark => Brightness.dark,
  };

  final ThemeData base = ThemeData(
    brightness: mode,
    colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: mode),
    useMaterial3: true,
  );

  return base.copyWith(
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    ),
    cardTheme: base.cardTheme.copyWith(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
  );
}

enum ThemeBrightness {
  light,
  dark,
}

ThemeBrightness brightnessFromThemeMode(ThemeMode mode, Brightness platform) {
  switch (mode) {
    case ThemeMode.light:
      return ThemeBrightness.light;
    case ThemeMode.dark:
      return ThemeBrightness.dark;
    case ThemeMode.system:
      return platform == Brightness.dark
          ? ThemeBrightness.dark
          : ThemeBrightness.light;
  }
}
