import 'package:drift/drift.dart';
import 'package:fridgie_app/core/db/app_database.dart';
import 'dart:developer' as developer;

enum ProductSort {
  nameAsc,
  nameDesc,
  categoryAsc,
  categoryDesc,
  expiryAsc,
  expiryDesc,
}

class ProductListItem {
  ProductListItem({required this.product, required this.nearestExpiry});

  final Product product;
  final DateTime? nearestExpiry;
}

class ProductRepository {
  ProductRepository(this._db);

  final AppDatabase _db;

  Future<int> createProduct(ProductsCompanion product) {
    return _db.into(_db.products).insert(product);
  }

  Future<void> updateProduct(Product product) {
    return _db
        .update(_db.products)
        .replace(product.copyWith(updatedAt: DateTime.now()));
  }

  Future<int> deleteProduct(int productId) {
    return (_db.delete(
      _db.products,
    )..where((tbl) => tbl.id.equals(productId))).go();
  }

  Future<void> markEaten(int productId) {
    return (_db.update(
      _db.products,
    )..where((Products t) => t.id.equals(productId))).write(
      ProductsCompanion(
        status: const Value<String>('eaten'),
        statusUpdatedAt: Value<DateTime>(DateTime.now()),
        updatedAt: Value<DateTime>(DateTime.now()),
      ),
    );
  }

  Future<void> markTrash(int productId) {
    return (_db.update(
      _db.products,
    )..where((Products t) => t.id.equals(productId))).write(
      ProductsCompanion(
        status: const Value<String>('trash'),
        statusUpdatedAt: Value<DateTime>(DateTime.now()),
        updatedAt: Value<DateTime>(DateTime.now()),
      ),
    );
  }

  Future<void> restoreActive(int productId) {
    return (_db.update(
      _db.products,
    )..where((Products t) => t.id.equals(productId))).write(
      ProductsCompanion(
        status: const Value<String>('active'),
        statusUpdatedAt: Value<DateTime>(DateTime.now()),
        updatedAt: Value<DateTime>(DateTime.now()),
      ),
    );
  }

  Future<List<Product>> getProductsByStatus(String status) {
    final Selectable<Product> query = _db.select(_db.products)
      ..where((Products t) => t.status.equals(status))
      ..orderBy(<OrderingTerm Function(Products)>[
        (Products t) => OrderingTerm.desc(t.updatedAt),
      ]);
    return query.get();
  }

  Future<List<Product>> autocompleteByName(
    String query, {
    int limit = 10,
  }) async {
    final String needle = query.trim().toLowerCase();
    if (needle.isEmpty) {
      return <Product>[];
    }

    final List<QueryRow> rows = await _db
        .customSelect(
          '''
      SELECT
        id,
        canonical_name,
        barcode,
        category,
        default_image_path,
        source,
        source_payload_json,
        status,
        status_updated_at,
        created_at,
        updated_at
      FROM products
      WHERE LOWER(canonical_name) LIKE ?
      ORDER BY canonical_name ASC
      LIMIT ?
      ''',
          variables: <Variable<Object>>[
            Variable<String>('%$needle%'),
            Variable<int>(limit),
          ],
          readsFrom: <ResultSetImplementation>{_db.products},
        )
        .get();

    return rows
        .map(
          (QueryRow row) => Product(
            id: row.read<int>('id'),
            canonicalName: row.read<String>('canonical_name'),
            barcode: row.readNullable<String>('barcode'),
            category: row.read<String>('category'),
            defaultImagePath: row.readNullable<String>('default_image_path'),
            source: row.read<String>('source'),
            sourcePayloadJson: row.readNullable<String>('source_payload_json'),
            status: row.read<String>('status'),
            statusUpdatedAt: row.readNullable<DateTime>('status_updated_at'),
            createdAt: row.read<DateTime>('created_at'),
            updatedAt: row.read<DateTime>('updated_at'),
          ),
        )
        .toList(growable: false);
  }

  Future<Product?> getByBarcode(String barcode) async {
    final List<String> candidates = _barcodeCandidates(barcode);
    if (candidates.isEmpty) {
      developer.log(
        'getByBarcode called with empty barcode after trim',
        name: 'ProductRepository',
      );
      return Future<Product?>.value(null);
    }

    developer.log(
      'Barcode lookup candidates=$candidates',
      name: 'ProductRepository',
    );

    final Selectable<Product> query = _db.select(_db.products)
      ..where((Products t) => t.barcode.isIn(candidates))
      ..orderBy(<OrderingTerm Function(Products)>[
        (Products t) => OrderingTerm.desc(t.updatedAt),
      ])
      ..limit(1);

    final Product? exact = await query.getSingleOrNull();
    if (exact != null) {
      developer.log(
        'Exact barcode match: productId=${exact.id}, barcode=${exact.barcode}, status=${exact.status}',
        name: 'ProductRepository',
      );
      return exact;
    }

    // Fallback: tolerate formatting differences in stored barcode values
    // (spaces/dashes/dots) and UPC-A <-> EAN-13 leading-zero variants.
    final Set<String> wantedKeys = _barcodeComparisonKeys(barcode);
    if (wantedKeys.isEmpty) {
      developer.log(
        'No comparison keys generated for barcode=$barcode',
        name: 'ProductRepository',
      );
      return null;
    }

    final List<Product> rows = await (_db.select(
      _db.products,
    )..where((Products t) => t.barcode.isNotNull())).get();

    Product? relaxed;
    for (final Product row in rows) {
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
        'Relaxed barcode match: productId=${relaxed.id}, stored=${relaxed.barcode}, input=$barcode, wantedKeys=$wantedKeys',
        name: 'ProductRepository',
      );
    } else {
      developer.log(
        'No barcode match found for input=$barcode, wantedKeys=$wantedKeys',
        name: 'ProductRepository',
      );
    }

    return relaxed;
  }

  Future<Product?> getLatestByCanonicalName(
    String canonicalName, {
    String? category,
  }) async {
    final String name = canonicalName.trim();
    if (name.isEmpty) {
      return null;
    }

    final String? normalizedCategory = category?.trim();
    final bool hasCategory =
        normalizedCategory != null && normalizedCategory.isNotEmpty;

    final StringBuffer sql = StringBuffer(
      '''
      SELECT
        id,
        canonical_name,
        barcode,
        category,
        default_image_path,
        source,
        source_payload_json,
        status,
        status_updated_at,
        created_at,
        updated_at
      FROM products
      WHERE LOWER(canonical_name) = LOWER(?)
      ''',
    );

    if (hasCategory) {
      sql.write(' AND LOWER(category) = LOWER(?)');
    }

    sql.write(
      '''
      ORDER BY CASE WHEN status = 'active' THEN 0 ELSE 1 END, updated_at DESC
      LIMIT 1
      ''',
    );

    final List<Variable<Object>> variables = <Variable<Object>>[
      Variable<String>(name),
      if (hasCategory) Variable<String>(normalizedCategory),
    ];

    final QueryRow? row = await _db
        .customSelect(
          sql.toString(),
          variables: variables,
          readsFrom: <ResultSetImplementation>{_db.products},
        )
        .getSingleOrNull();

    if (row == null) {
      developer.log(
        'No product match by canonical name. name=$name, category=$normalizedCategory',
        name: 'ProductRepository',
      );
      return null;
    }

    final Product product = Product(
      id: row.read<int>('id'),
      canonicalName: row.read<String>('canonical_name'),
      barcode: row.readNullable<String>('barcode'),
      category: row.read<String>('category'),
      defaultImagePath: row.readNullable<String>('default_image_path'),
      source: row.read<String>('source'),
      sourcePayloadJson: row.readNullable<String>('source_payload_json'),
      status: row.read<String>('status'),
      statusUpdatedAt: row.readNullable<DateTime>('status_updated_at'),
      createdAt: row.read<DateTime>('created_at'),
      updatedAt: row.read<DateTime>('updated_at'),
    );

    developer.log(
      'Canonical-name fallback matched productId=${product.id}, name=${product.canonicalName}, category=${product.category}, status=${product.status}',
      name: 'ProductRepository',
    );

    return product;
  }

  Future<List<ProductListItem>> getProductList({
    ProductSort sort = ProductSort.expiryAsc,
    String? status,
    String? category,
  }) async {
    final String orderBy = switch (sort) {
      ProductSort.nameAsc => 'p.canonical_name ASC',
      ProductSort.nameDesc => 'p.canonical_name DESC',
      ProductSort.categoryAsc => 'p.category ASC, p.canonical_name ASC',
      ProductSort.categoryDesc => 'p.category DESC, p.canonical_name ASC',
      ProductSort.expiryAsc =>
        'CASE WHEN MIN(pb.expiry_date) IS NULL THEN 1 ELSE 0 END, MIN(pb.expiry_date) ASC, p.canonical_name ASC',
      ProductSort.expiryDesc =>
        'CASE WHEN MIN(pb.expiry_date) IS NULL THEN 1 ELSE 0 END, MIN(pb.expiry_date) DESC, p.canonical_name ASC',
    };

    final List<String> whereParts = <String>[];
    if (status != null) {
      whereParts.add("p.status = '${status.replaceAll("'", "")}'");
    }
    if (category != null) {
      whereParts.add(
        "LOWER(p.category) = LOWER('${category.replaceAll("'", "")}')",
      );
    }
    final String whereClause = whereParts.isEmpty
        ? ''
        : 'WHERE ${whereParts.join(' AND ')}';

    final List<QueryRow> rows = await _db
        .customSelect(
          '''
      SELECT
        p.id,
        p.canonical_name,
        p.barcode,
        p.category,
        COALESCE(p.default_image_path, c.default_image_path) AS default_image_path,
        p.source,
        p.source_payload_json,
        p.status,
        p.status_updated_at,
        p.created_at,
        p.updated_at,
        MIN(pb.expiry_date) AS nearest_expiry
      FROM products p
      LEFT JOIN product_batches pb ON pb.product_id = p.id
      LEFT JOIN catalog_items c ON LOWER(c.canonical_name) = LOWER(p.canonical_name)
      $whereClause
      GROUP BY p.id
      ORDER BY $orderBy
      ''',
          readsFrom: <ResultSetImplementation>{
            _db.products,
            _db.productBatches,
            _db.catalogItems,
          },
        )
        .get();

    return rows
        .map((QueryRow row) {
          final Product product = Product(
            id: row.read<int>('id'),
            canonicalName: row.read<String>('canonical_name'),
            barcode: row.readNullable<String>('barcode'),
            category: row.read<String>('category'),
            defaultImagePath: row.readNullable<String>('default_image_path'),
            source: row.read<String>('source'),
            sourcePayloadJson: row.readNullable<String>('source_payload_json'),
            status: row.read<String>('status'),
            statusUpdatedAt: row.readNullable<DateTime>('status_updated_at'),
            createdAt: row.read<DateTime>('created_at'),
            updatedAt: row.read<DateTime>('updated_at'),
          );

          return ProductListItem(
            product: product,
            nearestExpiry: row.readNullable<DateTime>('nearest_expiry'),
          );
        })
        .toList(growable: false);
  }

  Future<Map<String, int>> getStatusCounts() async {
    final List<QueryRow> rows = await _db
        .customSelect(
          'SELECT status, COUNT(*) AS cnt FROM products GROUP BY status',
          readsFrom: <ResultSetImplementation>{_db.products},
        )
        .get();
    return <String, int>{
      for (final QueryRow row in rows)
        row.read<String>('status'): row.read<int>('cnt'),
    };
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
