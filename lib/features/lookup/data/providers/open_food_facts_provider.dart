import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:fridgie_app/features/lookup/data/models/lookup_result.dart';
import 'package:fridgie_app/features/lookup/domain/product_lookup_provider.dart';

class OpenFoodFactsProvider implements ProductLookupProvider {
  OpenFoodFactsProvider({Dio? dio, List<String>? baseUrls})
      : _dio = dio ?? Dio(),
        _baseUrls = baseUrls ??
            <String>[
              'https://world.openfoodfacts.org',
              'https://world.openbeautyfacts.org',
              'https://world.openpetfoodfacts.org',
              'https://world.openproductsfacts.org',
            ];

  final Dio _dio;
  final List<String> _baseUrls;

  @override
  String get providerName => 'open_food_facts_family';

  @override
  Future<LookupResult?> lookupByBarcode(String barcode) async {
    for (final String baseUrl in _baseUrls) {
      final LookupResult? result =
          await _lookupSingleBaseUrl(baseUrl: baseUrl, barcode: barcode);
      if (result != null) {
        return result;
      }
    }

    return null;
  }

  Future<LookupResult?> _lookupSingleBaseUrl({
    required String baseUrl,
    required String barcode,
  }) async {
    final String endpoint = '$baseUrl/api/v2/product/$barcode.json';

    try {
      final Response<dynamic> response = await _dio.get<dynamic>(endpoint);
      if (response.statusCode != 200 || response.data == null) {
        return null;
      }

      final Map<String, dynamic> data =
          Map<String, dynamic>.from(response.data as Map<dynamic, dynamic>);

      final int status = (data['status'] as num?)?.toInt() ?? 0;
      if (status != 1) {
        return null;
      }

      final Map<String, dynamic> product =
          Map<String, dynamic>.from(data['product'] as Map<dynamic, dynamic>);

      final String? name = _firstNonEmpty(<Object?>[
        product['product_name'],
        product['generic_name'],
        product['abbreviated_product_name'],
      ]);

      if (name == null) {
        return null;
      }

      return LookupResult(
        barcode: barcode,
        name: name,
        category: _firstNonEmpty(<Object?>[
          product['categories_old'],
          product['categories'],
        ]),
        imageUrl: _firstNonEmpty(<Object?>[
          product['image_front_url'],
          product['image_url'],
        ]),
        provider: providerName,
        payloadJson: jsonEncode(data),
      );
    } catch (_) {
      return null;
    }
  }

  String? _firstNonEmpty(List<Object?> values) {
    for (final Object? value in values) {
      final String candidate = (value ?? '').toString().trim();
      if (candidate.isNotEmpty) {
        return candidate;
      }
    }
    return null;
  }
}
