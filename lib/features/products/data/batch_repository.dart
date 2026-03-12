import 'package:drift/drift.dart';
import 'package:fridgie_app/core/db/app_database.dart';

class BatchRepository {
  BatchRepository(this._db);

  final AppDatabase _db;

  Future<int> createBatch(ProductBatchesCompanion batch) {
    return _db.into(_db.productBatches).insert(batch);
  }

  Future<void> updateBatch(ProductBatch batch) {
    return _db.update(_db.productBatches).replace(batch);
  }

  Future<int> deleteBatch(int batchId) {
    return (_db.delete(_db.productBatches)..where((tbl) => tbl.id.equals(batchId)))
        .go();
  }

  Future<int> duplicateBatch(
    int batchId, {
    DateTime? expiryDate,
    DateTime? buyDate,
  }) async {
    final ProductBatch original = await (_db.select(_db.productBatches)
          ..where((tbl) => tbl.id.equals(batchId)))
        .getSingle();

    return createBatch(
      ProductBatchesCompanion.insert(
        productId: original.productId,
        buyDate: Value(buyDate ?? original.buyDate),
        expiryDate: expiryDate ?? original.expiryDate,
        quantity: Value(original.quantity),
        notificationDaysBefore: Value(original.notificationDaysBefore),
        notificationTimeLocal: Value(original.notificationTimeLocal),
      ),
    );
  }

  Future<List<ProductBatch>> getBatchesByProduct(int productId) {
    return (_db.select(_db.productBatches)
          ..where((tbl) => tbl.productId.equals(productId))
          ..orderBy(<OrderingTerm Function(ProductBatches)>[
            (ProductBatches tbl) => OrderingTerm.asc(tbl.expiryDate),
          ]))
        .get();
  }
}
