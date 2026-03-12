import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fridgie_app/core/db/app_database.dart';
import 'package:fridgie_app/features/lookup/data/models/lookup_result.dart';
import 'package:fridgie_app/features/lookup/data/product_lookup_service.dart';
import 'package:fridgie_app/features/lookup/domain/product_lookup_provider.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(executor: NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('stores lookup payload in local cache when provider returns data', () async {
    final ProductLookupService service = ProductLookupService(
      db: db,
      providers: <ProductLookupProvider>[
        _FakeLookupProvider(
          providerName: 'fake_provider',
          result: const LookupResult(
            barcode: '123',
            name: 'Milk',
            category: 'dairy',
            imageUrl: 'https://example.com/milk.jpg',
            provider: 'fake_provider',
            payloadJson: '{"status":1}',
          ),
        ),
      ],
    );

    final LookupResult? result = await service.lookupByBarcode('123');

    expect(result, isNotNull);

    final cacheRows = await db.select(db.lookupCache).get();
    expect(cacheRows.length, 1);
    expect(cacheRows.first.barcode, '123');
    expect(cacheRows.first.provider, 'fake_provider');
  });

  test('returns null when all providers miss', () async {
    final ProductLookupService service = ProductLookupService(
      db: db,
      providers: <ProductLookupProvider>[
        _FakeLookupProvider(providerName: 'p1', result: null),
        _FakeLookupProvider(providerName: 'p2', result: null),
      ],
    );

    final LookupResult? result = await service.lookupByBarcode('999');

    expect(result, isNull);

    final cacheRows = await db.select(db.lookupCache).get();
    expect(cacheRows, isEmpty);
  });
}

class _FakeLookupProvider implements ProductLookupProvider {
  _FakeLookupProvider({required this.providerName, required this.result});

  @override
  final String providerName;

  final LookupResult? result;

  @override
  Future<LookupResult?> lookupByBarcode(String barcode) async => result;
}
