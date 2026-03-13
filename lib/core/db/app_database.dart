import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

class Products extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get canonicalName => text()();

  TextColumn get barcode => text().nullable()();

  TextColumn get category => text().withDefault(const Constant('unknown'))();

  TextColumn get defaultImagePath => text().nullable()();

  TextColumn get source => text().withDefault(const Constant('manual'))();

  TextColumn get sourcePayloadJson => text().nullable()();

  TextColumn get status => text().withDefault(const Constant('active'))();

  DateTimeColumn get statusUpdatedAt => dateTime().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('ProductBatch')
class ProductBatches extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get productId =>
      integer().references(Products, #id, onDelete: KeyAction.cascade)();

  DateTimeColumn get buyDate => dateTime().nullable()();

  DateTimeColumn get expiryDate => dateTime()();

  IntColumn get quantity => integer().withDefault(const Constant(1))();

  IntColumn get notificationDaysBefore => integer().withDefault(const Constant(3))();

  TextColumn get notificationTimeLocal =>
      text().withDefault(const Constant('09:00'))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class ProductImages extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get productId =>
      integer().references(Products, #id, onDelete: KeyAction.cascade)();

  TextColumn get barcode => text().nullable()();

  TextColumn get localPath => text()();

  IntColumn get width => integer().nullable()();

  IntColumn get height => integer().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class LookupCache extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get barcode => text()();

  TextColumn get provider => text()();

  TextColumn get payloadJson => text()();

  DateTimeColumn get fetchedAt => dateTime().withDefault(currentDateAndTime)();
}

class AppSettings extends Table {
  TextColumn get key => text()();

  TextColumn get value => text()();

  @override
  Set<Column<Object>>? get primaryKey => {key};
}

class Categories extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get name => text()();

  IntColumn get defaultExpiryDays =>
      integer().withDefault(const Constant(7))();
}

class CatalogItems extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get canonicalName => text()();

  TextColumn get barcode => text().nullable()();

  TextColumn get category => text().withDefault(const Constant('unknown'))();

  TextColumn get defaultImagePath => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

@DriftDatabase(
  tables: <Type>[
    Products,
    ProductBatches,
    ProductImages,
    LookupCache,
    AppSettings,
    Categories,
    CatalogItems,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase({QueryExecutor? executor}) : super(executor ?? _openConnection());

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();

      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_products_barcode ON products(barcode);',
      );
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_product_batches_product_id ON product_batches(product_id);',
      );
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_product_batches_expiry_date ON product_batches(expiry_date);',
      );
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_product_images_barcode ON product_images(barcode);',
      );
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_lookup_cache_barcode ON lookup_cache(barcode);',
      );
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_catalog_items_name ON catalog_items(canonical_name);',
      );
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_catalog_items_barcode ON catalog_items(barcode);',
      );

      await _seedDefaultSettings();
    },
    onUpgrade: (Migrator m, int from, int to) async {
      if (from < 2) {
        await customStatement(
          "ALTER TABLE products ADD COLUMN status TEXT NOT NULL DEFAULT 'active';",
        );
        await customStatement(
          'ALTER TABLE products ADD COLUMN status_updated_at INTEGER NULL;',
        );
      }
      if (from < 3) {
        await m.createTable(categories);
      }
      if (from < 4) {
        await m.createTable(catalogItems);
        await customStatement(
          '''
          INSERT INTO catalog_items (canonical_name, barcode, category, default_image_path, created_at, updated_at)
          SELECT p.canonical_name, p.barcode, p.category, p.default_image_path, p.created_at, p.updated_at
          FROM products p
          WHERE TRIM(p.canonical_name) != ''
          GROUP BY p.canonical_name
          ''',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_catalog_items_name ON catalog_items(canonical_name);',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_catalog_items_barcode ON catalog_items(barcode);',
        );
      }
    },
  );

  Future<void> _seedDefaultSettings() async {
    await batch((Batch b) {
      b.insertAllOnConflictUpdate(appSettings, <AppSettingsCompanion>[
        const AppSettingsCompanion(
          key: Value('default_notification_days_before'),
          value: Value('3'),
        ),
        const AppSettingsCompanion(
          key: Value('default_notification_time_local'),
          value: Value('09:00'),
        ),
        const AppSettingsCompanion(
          key: Value('default_sort'),
          value: Value('expiry_asc'),
        ),
      ]);
    });
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final Directory dbFolder = await getApplicationDocumentsDirectory();
    final File file = File(p.join(dbFolder.path, 'fridgie_app.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
