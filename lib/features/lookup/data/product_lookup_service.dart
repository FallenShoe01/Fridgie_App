import 'package:drift/drift.dart';
import 'package:fridgie_app/core/db/app_database.dart';
import 'package:fridgie_app/features/lookup/data/models/lookup_result.dart';
import 'package:fridgie_app/features/lookup/domain/product_lookup_provider.dart';

class ProductLookupService {
  ProductLookupService({
    required AppDatabase db,
    required List<ProductLookupProvider> providers,
  })  : _db = db,
        _providers = providers;

  final AppDatabase _db;
  final List<ProductLookupProvider> _providers;

  Future<LookupResult?> lookupByBarcode(String barcode) async {
    final String normalizedBarcode = barcode.trim();
    if (normalizedBarcode.isEmpty) {
      return null;
    }

    for (final ProductLookupProvider provider in _providers) {
      final LookupResult? result =
          await provider.lookupByBarcode(normalizedBarcode);
      if (result == null) {
        continue;
      }

      await _saveLookupCache(
        barcode: normalizedBarcode,
        provider: result.provider ?? provider.providerName,
        payloadJson: result.payloadJson,
      );

      return result;
    }

    return null;
  }

  Future<void> _saveLookupCache({
    required String barcode,
    required String provider,
    String? payloadJson,
  }) async {
    await _db.into(_db.lookupCache).insert(
          LookupCacheCompanion.insert(
            barcode: barcode,
            provider: provider,
            payloadJson: payloadJson ?? '{}',
            fetchedAt: Value(DateTime.now()),
          ),
        );
  }
}
