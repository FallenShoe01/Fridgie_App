import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fridgie_app/core/db/app_database.dart';
import 'package:fridgie_app/features/lookup/data/providers/open_food_facts_provider.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(executor: NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('exposes provider name', () {
    final OpenFoodFactsProvider provider = OpenFoodFactsProvider(db: db);
    expect(provider.providerName, 'open_food_facts');
  });

  test('returns null for empty barcode without requesting network', () async {
    final OpenFoodFactsProvider provider = OpenFoodFactsProvider(db: db);

    final result = await provider.lookupByBarcode('   ');

    expect(result, isNull);
  });
}
