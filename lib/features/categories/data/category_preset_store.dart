import 'package:drift/drift.dart';
import 'package:fridgie_app/core/db/app_database.dart';

class CategoryPreset {
  const CategoryPreset({
    required this.name,
    required this.defaultExpiryDays,
  });

  final String name;
  final int defaultExpiryDays;
}

class CategoryPresetStore {
  CategoryPresetStore(this._db);

  final AppDatabase _db;

  Future<List<CategoryPreset>> getAll() async {
    final List<Category> rows = await (_db.select(_db.categories)
          ..orderBy(<OrderingTerm Function(Categories)>[
            (Categories t) => OrderingTerm.asc(t.name),
          ]))
        .get();
    return rows
        .map(
          (Category r) => CategoryPreset(
            name: r.name,
            defaultExpiryDays: r.defaultExpiryDays,
          ),
        )
        .toList(growable: false);
  }

  Future<void> saveAll(List<CategoryPreset> items) async {
    await _db.transaction(() async {
      await _db.delete(_db.categories).go();
      for (final CategoryPreset item in items) {
        if (item.name.trim().isEmpty) continue;
        await _db.into(_db.categories).insert(
              CategoriesCompanion.insert(
                name: item.name.trim(),
                defaultExpiryDays: Value<int>(item.defaultExpiryDays),
              ),
            );
      }
    });
  }

  Future<void> deleteByName(String name) {
    return (_db.delete(_db.categories)
          ..where((Categories t) => t.name.equals(name)))
        .go();
  }
}
