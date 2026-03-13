import 'package:fridgie_app/app/presentation/main_shell_page.dart';
import 'package:fridgie_app/features/backup/presentation/backup_page.dart';
import 'package:fridgie_app/features/catalog/presentation/catalog_page.dart';
import 'package:fridgie_app/features/home/presentation/main_dashboard_page.dart';
import 'package:fridgie_app/features/products/presentation/add_product_page.dart';
import 'package:fridgie_app/features/products/presentation/product_list_page.dart';
import 'package:fridgie_app/features/settings/presentation/background_reliability_page.dart';
import 'package:fridgie_app/features/settings/presentation/settings_page.dart';
import 'package:go_router/go_router.dart';

final GoRouter appRouter = GoRouter(
  initialLocation: '/main',
  routes: <RouteBase>[
    GoRoute(
      path: '/',
      redirect: (context, state) => '/main',
    ),
    ShellRoute(
      builder: (context, state, child) => MainShellPage(child: child),
      routes: <RouteBase>[
        GoRoute(
          path: '/main',
          builder: (context, state) => const MainDashboardPage(),
        ),
        GoRoute(
          path: '/products',
          builder: (context, state) => const ProductListPage(),
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) => const SettingsPage(),
        ),
        GoRoute(
          path: '/catalog',
          builder: (context, state) => const CatalogPage(),
        ),
      ],
    ),
    GoRoute(
      path: '/add-product',
      builder: (context, state) {
        final int? editProductId =
            int.tryParse(state.uri.queryParameters['editProductId'] ?? '');
        final int? editCatalogItemId =
            int.tryParse(state.uri.queryParameters['editCatalogItemId'] ?? '');
        final String? catalogOnlyRaw = state.uri.queryParameters['catalogOnly'];
        final bool catalogOnlyAdd =
            catalogOnlyRaw != null && (catalogOnlyRaw == '1' || catalogOnlyRaw.toLowerCase() == 'true');

        return AddProductPage(
          editProductId: editProductId,
          editCatalogItemId: editCatalogItemId,
          catalogOnlyAdd: catalogOnlyAdd,
        );
      },
    ),
    GoRoute(
      path: '/edit-product',
      builder: (context, state) {
        final int id =
            int.tryParse(state.uri.queryParameters['id'] ?? '') ?? 0;
        return AddProductPage(editProductId: id);
      },
    ),
    GoRoute(
      path: '/background-reliability',
      builder: (context, state) => const BackgroundReliabilityPage(),
    ),
    GoRoute(
      path: '/backup',
      builder: (context, state) => const BackupPage(),
    ),
  ],
);
