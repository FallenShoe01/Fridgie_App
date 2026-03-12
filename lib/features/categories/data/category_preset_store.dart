import 'dart:convert';

import 'package:drift/drift.dart' as drift;
import 'package:fridgie_app/core/db/app_database.dart';

class CategoryPreset {
  const CategoryPreset({
    required this.name,
    required this.defaultExpiryDays,
  });

  final String name;
  final int defaultExpiryDays;

  Map<String, Object> toJson() => <String, Object>{
        'name': name,
        'defaultExpiryDays': defaultExpiryDays,
      };

  factory CategoryPreset.fromJson(Map<String, dynamic> json) {
    return CategoryPreset(
      name: (json['name'] as String? ?? '').trim(),
      defaultExpiryDays: (json['defaultExpiryDays'] as num? ?? 0).toInt(),
    );
  }
}

class CategoryPresetStore {
  CategoryPresetStore(this._db);

  final AppDatabase _db;
  static const String _settingsKey = 'category_presets_v1';

  Future<List<CategoryPreset>> getAll() async {
    final AppSetting? row = await (_db.select(_db.appSettings)
          ..where((AppSettings t) => t.key.equals(_settingsKey)))
        .getSingleOrNull();

    if (row == null || row.value.trim().isEmpty) {
      return <CategoryPreset>[];
    }

    final List<dynamic> decoded = jsonDecode(row.value) as List<dynamic>;
    return decoded
        .whereType<Map<dynamic, dynamic>>()
        .map(
          (Map<dynamic, dynamic> item) =>
              CategoryPreset.fromJson(Map<String, dynamic>.from(item)),
        )
        .where((CategoryPreset item) => item.name.isNotEmpty)
        .toList(growable: false);
  }

  Future<void> saveAll(List<CategoryPreset> items) {
    final String raw = jsonEncode(
      items
          .map((CategoryPreset item) => item.toJson())
          .toList(growable: false),
    );

    return _db.into(_db.appSettings).insertOnConflictUpdate(
          AppSettingsCompanion(
            key: const drift.Value<String>(_settingsKey),
            value: drift.Value<String>(raw),
          ),
        );
  }
}
