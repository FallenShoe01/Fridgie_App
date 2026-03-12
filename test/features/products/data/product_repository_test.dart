import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fridgie_app/core/db/app_database.dart';
import 'package:fridgie_app/features/products/data/batch_repository.dart';
import 'package:fridgie_app/features/products/data/product_repository.dart';

void main() {
  late AppDatabase db;
  late ProductRepository productRepository;
  late BatchRepository batchRepository;

  setUp(() {
    db = AppDatabase(executor: NativeDatabase.memory());
    productRepository = ProductRepository(db);
    batchRepository = BatchRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('product CRUD and autocomplete', () async {
    final int milkId = await productRepository.createProduct(
      ProductsCompanion.insert(
        canonicalName: 'Milk',
        barcode: Value('1111111111111'),
        category: Value('dairy'),
      ),
    );

    final List<Product> autocomplete =
        await productRepository.autocompleteByName('mil');
    expect(autocomplete.length, 1);
    expect(autocomplete.first.id, milkId);

    final Product milk = autocomplete.first;
    await productRepository.updateProduct(
      milk.copyWith(canonicalName: 'Fresh Milk'),
    );

    final List<Product> updated =
        await productRepository.autocompleteByName('fresh');
    expect(updated.length, 1);
    expect(updated.first.canonicalName, 'Fresh Milk');

    await productRepository.deleteProduct(milkId);
    final List<Product> afterDelete =
        await productRepository.autocompleteByName('fresh');
    expect(afterDelete, isEmpty);
  });

  test('sorting by name and expiry date', () async {
    final int milkId = await productRepository.createProduct(
      ProductsCompanion.insert(canonicalName: 'Milk'),
    );
    final int breadId = await productRepository.createProduct(
      ProductsCompanion.insert(canonicalName: 'Bread'),
    );

    final DateTime now = DateTime(2026, 3, 12);
    await batchRepository.createBatch(
      ProductBatchesCompanion.insert(
        productId: milkId,
        expiryDate: now.add(const Duration(days: 2)),
      ),
    );
    await batchRepository.createBatch(
      ProductBatchesCompanion.insert(
        productId: breadId,
        expiryDate: now.add(const Duration(days: 1)),
      ),
    );

    final List<ProductListItem> byName =
        await productRepository.getProductList(sort: ProductSort.nameAsc);
    expect(byName.map((ProductListItem e) => e.product.canonicalName).toList(),
        <String>['Bread', 'Milk']);

    final List<ProductListItem> byExpiry =
        await productRepository.getProductList(sort: ProductSort.expiryAsc);
    expect(byExpiry.first.product.canonicalName, 'Bread');
    expect(byExpiry.last.product.canonicalName, 'Milk');
  });

  test('duplicate batch clones values with optional new expiry', () async {
    final int milkId = await productRepository.createProduct(
      ProductsCompanion.insert(canonicalName: 'Milk'),
    );

    final int originalBatchId = await batchRepository.createBatch(
      ProductBatchesCompanion.insert(
        productId: milkId,
        buyDate: Value(DateTime(2026, 3, 1)),
        expiryDate: DateTime(2026, 3, 20),
        quantity: const Value(2),
        notificationDaysBefore: const Value(4),
        notificationTimeLocal: const Value('08:30'),
      ),
    );

    final int duplicateId = await batchRepository.duplicateBatch(
      originalBatchId,
      expiryDate: DateTime(2026, 3, 25),
    );

    final List<ProductBatch> allBatches =
        await batchRepository.getBatchesByProduct(milkId);

    expect(allBatches.length, 2);
    expect(allBatches.any((ProductBatch e) => e.id == originalBatchId), isTrue);
    expect(allBatches.any((ProductBatch e) => e.id == duplicateId), isTrue);

    final ProductBatch duplicated =
        allBatches.firstWhere((ProductBatch e) => e.id == duplicateId);
    expect(duplicated.expiryDate, DateTime(2026, 3, 25));
    expect(duplicated.quantity, 2);
    expect(duplicated.notificationDaysBefore, 4);
    expect(duplicated.notificationTimeLocal, '08:30');
  });
}
