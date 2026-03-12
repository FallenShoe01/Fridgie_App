import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fridgie_app/features/lookup/data/providers/open_food_facts_provider.dart';

void main() {
  test('returns normalized lookup result when status is found', () async {
    final Dio dio = Dio(
      BaseOptions(
        validateStatus: (_) => true,
      ),
    )
      ..httpClientAdapter = _FakeAdapter(
        statusCode: 200,
        body: <String, dynamic>{
          'status': 1,
          'product': <String, dynamic>{
            'product_name': 'Milk 3.2%',
            'categories': 'Dairy',
            'image_front_url': 'https://example.com/milk.jpg',
          },
        },
      );

    final OpenFoodFactsProvider provider = OpenFoodFactsProvider(
      dio: dio,
      baseUrls: <String>['https://world.openfoodfacts.org'],
    );

    final result = await provider.lookupByBarcode('1234567890123');

    expect(result, isNotNull);
    expect(result!.name, 'Milk 3.2%');
    expect(result.category, 'Dairy');
    expect(result.imageUrl, 'https://example.com/milk.jpg');
    expect(result.provider, 'open_food_facts_family');
    expect(result.payloadJson, isNotEmpty);
  });

  test('returns null when product is not found', () async {
    final Dio dio = Dio(
      BaseOptions(
        validateStatus: (_) => true,
      ),
    )
      ..httpClientAdapter = _FakeAdapter(
        statusCode: 200,
        body: <String, dynamic>{
          'status': 0,
        },
      );

    final OpenFoodFactsProvider provider = OpenFoodFactsProvider(
      dio: dio,
      baseUrls: <String>['https://world.openfoodfacts.org'],
    );

    final result = await provider.lookupByBarcode('not-found');

    expect(result, isNull);
  });
}

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter({required this.statusCode, required this.body});

  final int statusCode;
  final Map<String, dynamic> body;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final List<int> bytes = utf8.encode(jsonEncode(body));

    return ResponseBody.fromBytes(
      bytes,
      statusCode,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }
}
