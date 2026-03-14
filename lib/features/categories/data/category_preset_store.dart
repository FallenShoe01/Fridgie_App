import 'package:drift/drift.dart';
import 'package:fridgie_app/core/db/app_database.dart';

class CategoryPreset {
  const CategoryPreset({required this.name, required this.defaultExpiryDays});

  final String name;
  final int defaultExpiryDays;
}

class CategoryPresetStore {
  CategoryPresetStore(this._db);

  final AppDatabase _db;

  Future<List<CategoryPreset>> getAll() async {
    final List<Category> rows =
        await (_db.select(_db.categories)
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
        await _db
            .into(_db.categories)
            .insert(
              CategoriesCompanion.insert(
                name: item.name.trim(),
                defaultExpiryDays: Value<int>(item.defaultExpiryDays),
              ),
            );
      }
    });
  }

  Future<void> add(CategoryPreset item) async {
    final String name = item.name.trim();
    if (name.isEmpty) {
      return;
    }

    final QueryRow? existing = await _db
        .customSelect(
          'SELECT id FROM categories WHERE LOWER(name) = LOWER(?) LIMIT 1',
          variables: <Variable<Object>>[Variable<String>(name)],
          readsFrom: <ResultSetImplementation>{_db.categories},
        )
        .getSingleOrNull();

    if (existing == null) {
      await _db
          .into(_db.categories)
          .insert(
            CategoriesCompanion.insert(
              name: name,
              defaultExpiryDays: Value<int>(item.defaultExpiryDays),
            ),
          );
      return;
    }

    // Do not overwrite an existing category's defaultExpiryDays here.
    // We only ensure the name exists (case-insensitively). Editing defaults
    // should be done explicitly via the UI (updateByName).
    await (_db.update(
      _db.categories,
    )..where((Categories t) => t.id.equals(existing.read<int>('id')))).write(
      CategoriesCompanion(
        name: Value<String>(name),
      ),
    );
  }

  Future<void> updateByName(String oldName, CategoryPreset newValue) async {
    final String newName = newValue.name.trim();
    if (newName.isEmpty) return;

    final QueryRow? existing = await _db
        .customSelect(
          'SELECT id FROM categories WHERE LOWER(name) = LOWER(?) LIMIT 1',
          variables: <Variable<Object>>[Variable<String>(oldName.trim())],
          readsFrom: <ResultSetImplementation>{_db.categories},
        )
        .getSingleOrNull();

    if (existing == null) {
      // Insert as new if old not found
      await _db.into(_db.categories).insert(
        CategoriesCompanion.insert(
          name: newName,
          defaultExpiryDays: Value<int>(newValue.defaultExpiryDays),
        ),
      );
      return;
    }

    await (_db.update(
      _db.categories,
    )..where((Categories t) => t.id.equals(existing.read<int>('id')))).write(
      CategoriesCompanion(
        name: Value<String>(newName),
        defaultExpiryDays: Value<int>(newValue.defaultExpiryDays),
      ),
    );
  }

  Future<void> deleteByName(String name) {
    return (_db.delete(
      _db.categories,
    )..where((Categories t) => t.name.equals(name))).go();
  }
}
