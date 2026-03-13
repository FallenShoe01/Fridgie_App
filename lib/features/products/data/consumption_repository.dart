import 'package:drift/drift.dart';
import 'package:fridgie_app/core/db/app_database.dart';

class ConsumptionRepository {
  ConsumptionRepository(this._db);

  final AppDatabase _db;

  Future<int> logConsumption({
    required int productId,
    required int batchId,
    required String action,
    required int quantity,
    required DateTime batchExpiryDate,
  }) {
    return _db.into(_db.consumptionEvents).insert(
          ConsumptionEventsCompanion.insert(
            productId: productId,
            batchId: Value<int?>(batchId),
            action: action,
            quantity: Value<int>(quantity),
            batchExpiryDate: Value<DateTime?>(batchExpiryDate),
          ),
        );
  }

  Future<List<ConsumptionEvent>> getByProduct(int productId) {
    return (_db.select(_db.consumptionEvents)
          ..where((ConsumptionEvents t) => t.productId.equals(productId))
          ..orderBy(<OrderingTerm Function(ConsumptionEvents)>[
            (ConsumptionEvents t) => OrderingTerm.desc(t.createdAt),
          ]))
        .get();
  }
}
