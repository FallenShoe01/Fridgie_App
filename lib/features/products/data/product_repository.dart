import 'package:drift/drift.dart';
import 'package:fridgie_app/core/db/app_database.dart';

enum ProductSort {
  nameAsc,
  nameDesc,
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
    return _db.update(_db.products).replace(
          product.copyWith(updatedAt: DateTime.now()),
        );
  }

  Future<int> deleteProduct(int productId) {
    return (_db.delete(_db.products)..where((tbl) => tbl.id.equals(productId)))
        .go();
  }

  Future<void> markEaten(int productId) {
    return (_db.update(_db.products)..where((Products t) => t.id.equals(productId)))
        .write(
      ProductsCompanion(
        status: const Value<String>('eaten'),
        statusUpdatedAt: Value<DateTime>(DateTime.now()),
        updatedAt: Value<DateTime>(DateTime.now()),
      ),
    );
  }

  Future<void> markTrash(int productId) {
    return (_db.update(_db.products)..where((Products t) => t.id.equals(productId)))
        .write(
      ProductsCompanion(
        status: const Value<String>('trash'),
        statusUpdatedAt: Value<DateTime>(DateTime.now()),
        updatedAt: Value<DateTime>(DateTime.now()),
      ),
    );
  }

  Future<void> restoreActive(int productId) {
    return (_db.update(_db.products)..where((Products t) => t.id.equals(productId)))
        .write(
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
  }) {
    final String needle = query.trim();
    if (needle.isEmpty) {
      return Future<List<Product>>.value(<Product>[]);
    }

    final Selectable<Product> base = _db.select(_db.products)
      ..where((tbl) => tbl.canonicalName.like('%$needle%'))
      ..orderBy(<OrderingTerm Function(Products)>[
        (Products tbl) => OrderingTerm.asc(tbl.canonicalName),
      ])
      ..limit(limit);

    return base.get();
  }

  Future<List<ProductListItem>> getProductList({
    ProductSort sort = ProductSort.expiryAsc,
    String? status,
  }) async {
    final String orderBy = switch (sort) {
      ProductSort.nameAsc => 'p.canonical_name ASC',
      ProductSort.nameDesc => 'p.canonical_name DESC',
      ProductSort.expiryAsc =>
        'CASE WHEN MIN(pb.expiry_date) IS NULL THEN 1 ELSE 0 END, MIN(pb.expiry_date) ASC, p.canonical_name ASC',
      ProductSort.expiryDesc =>
        'CASE WHEN MIN(pb.expiry_date) IS NULL THEN 1 ELSE 0 END, MIN(pb.expiry_date) DESC, p.canonical_name ASC',
    };

    final String whereClause =
      status == null ? '' : "WHERE p.status = '${status.replaceAll("'", "")}'";

    final List<QueryRow> rows = await _db.customSelect(
      '''
      SELECT
        p.id,
        p.canonical_name,
        p.barcode,
        p.category,
        p.default_image_path,
        p.source,
        p.source_payload_json,
        p.status,
        p.status_updated_at,
        p.created_at,
        p.updated_at,
        MIN(pb.expiry_date) AS nearest_expiry
      FROM products p
      LEFT JOIN product_batches pb ON pb.product_id = p.id
      $whereClause
      GROUP BY p.id
      ORDER BY $orderBy
      ''',
      readsFrom: <ResultSetImplementation>{_db.products, _db.productBatches},
    ).get();

    return rows.map((QueryRow row) {
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
    }).toList(growable: false);
  }
}
