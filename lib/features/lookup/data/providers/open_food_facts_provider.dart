import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:fridgie_app/core/db/app_database.dart' as appdb;
import 'package:fridgie_app/features/lookup/data/models/lookup_result.dart';
import 'package:fridgie_app/features/lookup/domain/product_lookup_provider.dart';
import 'package:fridgie_app/core/off_environment.dart';
import 'package:openfoodfacts/openfoodfacts.dart';

class OpenFoodFactsProvider implements ProductLookupProvider {
  OpenFoodFactsProvider({required appdb.AppDatabase db}) : _db = db;

  final appdb.AppDatabase _db;

  static const String _settingsUseAccountKey = 'lookup_off_account_enabled';
  static const String _settingsUsernameKey = 'lookup_off_username';
  static const String _settingsPasswordKey = 'lookup_off_password';

  // Intentionally below OFF read-product limit (100 req/min) to avoid bans.
  static const Duration _minRequestInterval = Duration(seconds: 2);
  static const Duration _accountRefreshInterval = Duration(seconds: 30);
  static DateTime? _lastRequestAtUtc;
  static DateTime? _lastAccountRefreshUtc;
  static Future<void> _rateLimitChain = Future<void>.value();

  @override
  String get providerName => 'open_food_facts';

  @override
  Future<LookupResult?> lookupByBarcode(String barcode) async {
    final String normalizedBarcode = barcode.trim();
    if (normalizedBarcode.isEmpty) {
      return null;
    }

    await _refreshConfiguredUserIfNeeded();
    await _applyClientSideRateLimit();

    final ProductQueryConfiguration config = ProductQueryConfiguration(
      normalizedBarcode,
      version: ProductQueryVersion.v3,
      fields: <ProductField>[
        ProductField.NAME,
        ProductField.GENERIC_NAME,
        ProductField.CATEGORIES,
        ProductField.CATEGORIES_TAGS,
        ProductField.IMAGE_FRONT_URL,
      ],
    );

    try {
      final ProductResultV3 response = await OpenFoodAPIClient.getProductV3(
        config,
        user: OpenFoodAPIConfiguration.globalUser,
        uriHelper: kOffLookupUriHelper,
      );

      if (response.status != ProductResultV3.statusSuccess &&
          response.status != ProductResultV3.statusWarning) {
        return null;
      }

      final Product? product = response.product;
      if (product == null) {
        return null;
      }

      final String? name = _firstNonEmpty(<Object?>[
        product.productName,
        product.genericName,
        product.abbreviatedName,
      ]);

      if (name == null) {
        return null;
      }

      final String? categoryFromTags = _firstNonEmpty(<Object?>[
        product.categoriesTags?.isNotEmpty == true
            ? product.categoriesTags!.first
            : null,
      ]);

      final Map<String, dynamic> payload = response.toJson();

      return LookupResult(
        barcode: normalizedBarcode,
        name: name,
        category: _firstNonEmpty(<Object?>[
          product.categories,
          categoryFromTags,
        ]),
        imageUrl: _firstNonEmpty(<Object?>[
          product.imageFrontUrl,
          product.imageFrontSmallUrl,
        ]),
        provider: providerName,
        payloadJson: jsonEncode(payload),
      );
    } on TooManyRequestsException catch (e) {
      debugPrint('[OFFApi] TooManyRequestsException: $e');
      return null;
    } on Exception catch (e) {
      debugPrint('[OFFApi] SDK lookup exception: $e');
      return null;
    } catch (e) {
      debugPrint('[OFFApi] Unknown lookup exception: $e');
      return null;
    }
  }

  Future<void> _refreshConfiguredUserIfNeeded() async {
    final DateTime nowUtc = DateTime.now().toUtc();
    final DateTime? lastRefreshUtc = _lastAccountRefreshUtc;
    if (lastRefreshUtc != null &&
        nowUtc.difference(lastRefreshUtc) < _accountRefreshInterval) {
      return;
    }

    _lastAccountRefreshUtc = nowUtc;

        final List<appdb.AppSetting> rows = await (_db.select(_db.appSettings)
          ..where((appdb.AppSettings tbl) =>
              tbl.key.isIn(<String>[
                _settingsUseAccountKey,
                _settingsUsernameKey,
                _settingsPasswordKey,
              ])))
        .get();

    final Map<String, String> map = <String, String>{
      for (final appdb.AppSetting row in rows) row.key: row.value,
    };

    final bool useAccount =
        (map[_settingsUseAccountKey] ?? 'false').trim().toLowerCase() == 'true';
    final String username = (map[_settingsUsernameKey] ?? '').trim();
    final String password = (map[_settingsPasswordKey] ?? '').trim();

    if (useAccount && username.isNotEmpty && password.isNotEmpty) {
      OpenFoodAPIConfiguration.globalUser = User(
        userId: username,
        password: password,
      );
    } else {
      OpenFoodAPIConfiguration.globalUser = null;
    }
  }

  Future<void> _applyClientSideRateLimit() {
    final Future<void> next = _rateLimitChain.then((_) async {
      final DateTime nowUtc = DateTime.now().toUtc();
      final DateTime? lastUtc = _lastRequestAtUtc;
      if (lastUtc != null) {
        final Duration elapsed = nowUtc.difference(lastUtc);
        if (elapsed < _minRequestInterval) {
          await Future<void>.delayed(_minRequestInterval - elapsed);
        }
      }
      _lastRequestAtUtc = DateTime.now().toUtc();
    });

    _rateLimitChain = next.catchError((Object _) {});
    return next;
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
