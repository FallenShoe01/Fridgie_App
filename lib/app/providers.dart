import 'package:dio/dio.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fridgie_app/app/settings_controller.dart';
import 'package:fridgie_app/core/db/app_database.dart';
import 'package:fridgie_app/features/backup/data/backup_service.dart';
import 'package:fridgie_app/features/catalog/data/catalog_repository.dart';
import 'package:fridgie_app/features/categories/data/category_preset_store.dart';
import 'package:fridgie_app/features/images/data/image_service.dart';
import 'package:fridgie_app/features/lookup/data/product_lookup_service.dart';
import 'package:fridgie_app/features/lookup/data/providers/open_food_facts_provider.dart';
import 'package:fridgie_app/features/lookup/domain/product_lookup_provider.dart';
import 'package:fridgie_app/features/notifications/data/notification_service.dart';
import 'package:fridgie_app/features/products/data/batch_repository.dart';
import 'package:fridgie_app/features/products/data/consumption_repository.dart';
import 'package:fridgie_app/features/products/data/product_repository.dart';
import 'package:fridgie_app/features/update/data/github_update_service.dart';

final dbProvider = Provider<AppDatabase>((Ref ref) {
  final AppDatabase db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final dioProvider = Provider<Dio>((Ref ref) => Dio());

final productRepositoryProvider =
    Provider<ProductRepository>((Ref ref) {
  return ProductRepository(ref.read(dbProvider));
});

final catalogRepositoryProvider =
    Provider<CatalogRepository>((Ref ref) {
  return CatalogRepository(ref.read(dbProvider));
});

final batchRepositoryProvider =
    Provider<BatchRepository>((Ref ref) {
  return BatchRepository(ref.read(dbProvider));
});

final consumptionRepositoryProvider =
    Provider<ConsumptionRepository>((Ref ref) {
  return ConsumptionRepository(ref.read(dbProvider));
});

final imageServiceProvider =
    Provider<ImageService>((Ref ref) {
  return ImageService(dio: ref.read(dioProvider));
});

final productLookupProvidersProvider =
    Provider<List<ProductLookupProvider>>((Ref ref) {
  return <ProductLookupProvider>[
    OpenFoodFactsProvider(dio: ref.read(dioProvider)),
  ];
});

final productLookupServiceProvider =
    Provider<ProductLookupService>((Ref ref) {
  return ProductLookupService(
    db: ref.read(dbProvider),
    providers: ref.read(productLookupProvidersProvider),
  );
});

// Shared singleton plugin instance used across the app. Initialized from `main`.
final FlutterLocalNotificationsPlugin notificationsPlugin =
    FlutterLocalNotificationsPlugin();

final notificationsPluginProvider = Provider<FlutterLocalNotificationsPlugin>(
  (Ref ref) => notificationsPlugin,
);

final notificationServiceProvider = Provider<NotificationService>((Ref ref) {
  return NotificationService(ref.read(notificationsPluginProvider));
});

final githubUpdateServiceProvider = Provider<GithubUpdateService>((Ref ref) {
  return GithubUpdateService(dio: ref.read(dioProvider));
});

final backupServiceProvider = Provider<BackupService>((Ref ref) {
  return BackupService(db: ref.read(dbProvider));
});

final categoryPresetStoreProvider = Provider<CategoryPresetStore>((Ref ref) {
  return CategoryPresetStore(ref.read(dbProvider));
});

final settingsControllerProvider =
    StateNotifierProvider<SettingsController, AsyncValue<SettingsState>>(
  (Ref ref) => SettingsController(ref.read(dbProvider)),
);

/// Shared one-shot status filter: set by Main dashboard before navigating to
/// Products tab so the list pre-selects that filter.
final productStatusFilterProvider = StateProvider<String?>((Ref ref) => null);
