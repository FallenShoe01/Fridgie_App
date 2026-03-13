import 'package:drift/drift.dart';
import 'package:fridgie_app/core/db/app_database.dart';

class CatalogRepository {
  CatalogRepository(this._db);

  final AppDatabase _db;

  Future<void> upsertCatalogItem({
    required String canonicalName,
    String? barcode,
    required String category,
    String? defaultImagePath,
  }) async {
    final String name = canonicalName.trim();
    if (name.isEmpty) {
      return;
    }

    final String? normalizedBarcode = _normalizeNullable(barcode);
    final String normalizedCategory =
        category.trim().isEmpty ? 'unknown' : category.trim();
    final String? normalizedImagePath = _normalizeNullable(defaultImagePath);

    final Selectable<CatalogItem> query = _db.select(_db.catalogItems)
      ..where((CatalogItems t) => t.canonicalName.equals(name))
      ..limit(1);

    final CatalogItem? existing = await query.getSingleOrNull();
    if (existing == null) {
      await _db.into(_db.catalogItems).insert(
            CatalogItemsCompanion.insert(
              canonicalName: name,
              barcode: Value<String?>(normalizedBarcode),
              category: Value<String>(normalizedCategory),
              defaultImagePath: Value<String?>(normalizedImagePath),
            ),
          );
      return;
    }

    await (_db.update(_db.catalogItems)..where((CatalogItems t) => t.id.equals(existing.id)))
        .write(
      CatalogItemsCompanion(
        barcode: Value<String?>(normalizedBarcode ?? existing.barcode),
        category: Value<String>(normalizedCategory),
        defaultImagePath: Value<String?>(
          normalizedImagePath ?? existing.defaultImagePath,
        ),
        updatedAt: Value<DateTime>(DateTime.now()),
      ),
    );
  }

  Future<List<CatalogItem>> autocompleteByName(
    String query, {
    int limit = 10,
  }) {
    final String needle = query.trim();
    if (needle.isEmpty) {
      return Future<List<CatalogItem>>.value(<CatalogItem>[]);
    }

    final Selectable<CatalogItem> base = _db.select(_db.catalogItems)
      ..where((CatalogItems tbl) => tbl.canonicalName.like('%$needle%'))
      ..orderBy(<OrderingTerm Function(CatalogItems)>[
        (CatalogItems tbl) => OrderingTerm.asc(tbl.canonicalName),
      ])
      ..limit(limit);

    return base.get();
  }

  Future<List<CatalogItem>> getAllCatalogItems() {
    final Selectable<CatalogItem> query = _db.select(_db.catalogItems)
      ..orderBy(<OrderingTerm Function(CatalogItems)>[
        (CatalogItems t) => OrderingTerm.asc(t.canonicalName),
      ]);
    return query.get();
  }

  Future<CatalogItem?> getById(int id) {
    final Selectable<CatalogItem> query = _db.select(_db.catalogItems)
      ..where((CatalogItems t) => t.id.equals(id))
      ..limit(1);
    return query.getSingleOrNull();
  }

  Future<void> updateCatalogItem(
    CatalogItem item, {
    required String canonicalName,
    String? barcode,
    required String category,
    String? defaultImagePath,
  }) {
    final String normalizedName = canonicalName.trim();
    final String normalizedCategory =
        category.trim().isEmpty ? 'unknown' : category.trim();
    final String? normalizedBarcode = _normalizeNullable(barcode);
    final String? normalizedImagePath = _normalizeNullable(defaultImagePath);

    return (_db.update(_db.catalogItems)
          ..where((CatalogItems t) => t.id.equals(item.id)))
        .write(
      CatalogItemsCompanion(
        canonicalName: Value<String>(normalizedName),
        barcode: Value<String?>(normalizedBarcode),
        category: Value<String>(normalizedCategory),
        defaultImagePath: Value<String?>(normalizedImagePath),
        updatedAt: Value<DateTime>(DateTime.now()),
      ),
    );
  }

  String? _normalizeNullable(String? value) {
    final String trimmed = (value ?? '').trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }
}
