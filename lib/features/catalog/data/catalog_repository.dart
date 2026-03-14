import 'package:drift/drift.dart';
import 'package:fridgie_app/core/db/app_database.dart';
import 'dart:developer' as developer;

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
    final String normalizedCategory = category.trim().isEmpty
        ? 'unknown'
        : category.trim();
    final String? normalizedImagePath = _normalizeNullable(defaultImagePath);

    final Selectable<CatalogItem> query = _db.select(_db.catalogItems)
      ..where((CatalogItems t) => t.canonicalName.equals(name))
      ..limit(1);

    final CatalogItem? existing = await query.getSingleOrNull();
    if (existing == null) {
      await _db
          .into(_db.catalogItems)
          .insert(
            CatalogItemsCompanion.insert(
              canonicalName: name,
              barcode: Value<String?>(normalizedBarcode),
              category: Value<String>(normalizedCategory),
              defaultImagePath: Value<String?>(normalizedImagePath),
            ),
          );
      return;
    }

    await (_db.update(
      _db.catalogItems,
    )..where((CatalogItems t) => t.id.equals(existing.id))).write(
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
  }) async {
    final String needle = query.trim().toLowerCase();
    if (needle.isEmpty) {
      return <CatalogItem>[];
    }

    final List<QueryRow> rows = await _db
        .customSelect(
          '''
      SELECT id, canonical_name, barcode, category, default_image_path, created_at, updated_at
      FROM catalog_items
      WHERE LOWER(canonical_name) LIKE ?
      ORDER BY canonical_name ASC
      LIMIT ?
      ''',
          variables: <Variable<Object>>[
            Variable<String>('%$needle%'),
            Variable<int>(limit),
          ],
          readsFrom: <ResultSetImplementation>{_db.catalogItems},
        )
        .get();

    return rows
        .map(
          (QueryRow row) => CatalogItem(
            id: row.read<int>('id'),
            canonicalName: row.read<String>('canonical_name'),
            barcode: row.readNullable<String>('barcode'),
            category: row.read<String>('category'),
            defaultImagePath: row.readNullable<String>('default_image_path'),
            createdAt: row.read<DateTime>('created_at'),
            updatedAt: row.read<DateTime>('updated_at'),
          ),
        )
        .toList(growable: false);
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

  Future<CatalogItem?> getByBarcode(String barcode) async {
    final List<String> candidates = _barcodeCandidates(barcode);
    if (candidates.isEmpty) {
      developer.log(
        'getByBarcode called with empty barcode after trim',
        name: 'CatalogRepository',
      );
      return Future.value(null);
    }

    developer.log(
      'Barcode lookup candidates=$candidates',
      name: 'CatalogRepository',
    );

    final Selectable<CatalogItem> query = _db.select(_db.catalogItems)
      ..where((CatalogItems t) => t.barcode.isIn(candidates))
      ..limit(1);

    final CatalogItem? exact = await query.getSingleOrNull();
    if (exact != null) {
      developer.log(
        'Exact barcode match: catalogItemId=${exact.id}, barcode=${exact.barcode}',
        name: 'CatalogRepository',
      );
      return exact;
    }

    final Set<String> wantedKeys = _barcodeComparisonKeys(barcode);
    final List<CatalogItem> rows = await (_db.select(
      _db.catalogItems,
    )..where((CatalogItems t) => t.barcode.isNotNull())).get();

    CatalogItem? relaxed;
    for (final CatalogItem row in rows) {
      final String? stored = row.barcode;
      if (stored == null || stored.trim().isEmpty) {
        continue;
      }

      final Set<String> storedKeys = _barcodeComparisonKeys(stored);
      final bool intersects = storedKeys.any(wantedKeys.contains);
      if (!intersects) {
        continue;
      }

      if (relaxed == null || row.updatedAt.isAfter(relaxed.updatedAt)) {
        relaxed = row;
      }
    }

    if (relaxed != null) {
      developer.log(
        'Relaxed barcode match: catalogItemId=${relaxed.id}, stored=${relaxed.barcode}, input=$barcode, wantedKeys=$wantedKeys',
        name: 'CatalogRepository',
      );
    } else {
      developer.log(
        'No barcode match found for input=$barcode, wantedKeys=$wantedKeys',
        name: 'CatalogRepository',
      );
    }

    return relaxed;
  }

  Future<void> deleteById(int id) {
    return (_db.delete(
      _db.catalogItems,
    )..where((CatalogItems t) => t.id.equals(id))).go();
  }

  Future<void> updateCatalogItem(
    CatalogItem item, {
    required String canonicalName,
    String? barcode,
    required String category,
    String? defaultImagePath,
  }) {
    final String normalizedName = canonicalName.trim();
    final String normalizedCategory = category.trim().isEmpty
        ? 'unknown'
        : category.trim();
    final String? normalizedBarcode = _normalizeNullable(barcode);
    final String? normalizedImagePath = _normalizeNullable(defaultImagePath);

    return (_db.update(
      _db.catalogItems,
    )..where((CatalogItems t) => t.id.equals(item.id))).write(
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

  List<String> _barcodeCandidates(String barcode) {
    final String trimmed = barcode.trim();
    if (trimmed.isEmpty) {
      return <String>[];
    }

    final Set<String> out = <String>{trimmed};

    // Some scanners alternate UPC-A (12 digits) and EAN-13 (leading 0).
    final String digitsOnly = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitsOnly.isNotEmpty) {
      out.add(digitsOnly);
      if (digitsOnly.length == 12) {
        out.add('0$digitsOnly');
      }
      if (digitsOnly.length == 13 && digitsOnly.startsWith('0')) {
        out.add(digitsOnly.substring(1));
      }
    }

    return out.toList(growable: false);
  }

  Set<String> _barcodeComparisonKeys(String barcode) {
    final String trimmed = barcode.trim();
    if (trimmed.isEmpty) {
      return <String>{};
    }

    final Set<String> out = <String>{trimmed.toLowerCase()};

    final String compact =
        trimmed.replaceAll(RegExp(r'[\s\-\.]'), '').toLowerCase();
    if (compact.isNotEmpty) {
      out.add(compact);
    }

    final String digitsOnly = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitsOnly.isNotEmpty) {
      out.add(digitsOnly);
      if (digitsOnly.length == 12) {
        out.add('0$digitsOnly');
      }
      if (digitsOnly.length == 13 && digitsOnly.startsWith('0')) {
        out.add(digitsOnly.substring(1));
      }
    }

    return out;
  }
}
