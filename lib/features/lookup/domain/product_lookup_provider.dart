import 'package:fridgie_app/features/lookup/data/models/lookup_result.dart';

abstract class ProductLookupProvider {
  String get providerName;

  Future<LookupResult?> lookupByBarcode(String barcode);
}
