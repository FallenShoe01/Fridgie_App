import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fridgie_app/app/theme/app_theme.dart';
import 'package:fridgie_app/core/db/app_database.dart';

class SettingsState {
  const SettingsState({
    required this.themeMode,
    required this.accent,
    required this.localeCode,
  });

  final ThemeMode themeMode;
  final AppAccent accent;
  final String localeCode;

  SettingsState copyWith({
    ThemeMode? themeMode,
    AppAccent? accent,
    String? localeCode,
  }) {
    return SettingsState(
      themeMode: themeMode ?? this.themeMode,
      accent: accent ?? this.accent,
      localeCode: localeCode ?? this.localeCode,
    );
  }
}

class SettingsController extends StateNotifier<AsyncValue<SettingsState>> {
  SettingsController(this._db, {SettingsState? initialState})
      : super(
          initialState == null
              ? const AsyncValue<SettingsState>.loading()
              : AsyncValue<SettingsState>.data(initialState),
        ) {
    if (initialState == null) {
      _load();
    }
  }

  final AppDatabase _db;

  Future<void> _load() async {
    try {
      final List<AppSetting> rows = await _db.select(_db.appSettings).get();
      final Map<String, String> map = <String, String>{
        for (final AppSetting row in rows) row.key: row.value,
      };

      state = AsyncValue<SettingsState>.data(
        SettingsState(
          themeMode: _themeModeFromString(map['ui_theme_mode']),
          accent: accentFromString(map['ui_accent'] ?? 'teal'),
          localeCode: _localeFromString(map['ui_locale']),
        ),
      );
    } catch (e, st) {
      state = AsyncValue<SettingsState>.error(e, st);
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    await _upsert('ui_theme_mode', mode.name);
    state = state.whenData((SettingsState value) => value.copyWith(themeMode: mode));
  }

  Future<void> setAccent(AppAccent accent) async {
    await _upsert('ui_accent', accent.name);
    state = state.whenData((SettingsState value) => value.copyWith(accent: accent));
  }

  Future<void> setLocale(String localeCode) async {
    await _upsert('ui_locale', localeCode);
    state = state.whenData(
      (SettingsState value) => value.copyWith(localeCode: localeCode),
    );
  }

  Future<void> _upsert(String key, String value) {
    return _db.into(_db.appSettings).insertOnConflictUpdate(
          AppSettingsCompanion(
            key: drift.Value<String>(key),
            value: drift.Value<String>(value),
          ),
        );
  }

  ThemeMode _themeModeFromString(String? raw) {
    return switch (raw) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  String _localeFromString(String? raw) {
    return switch (raw) {
      'uk' => 'uk',
      'ru' => 'ru',
      _ => 'en',
    };
  }
}
