import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fridgie_app/app/providers.dart';
import 'package:fridgie_app/features/products/data/product_repository.dart';
import 'package:go_router/go_router.dart';

class MainDashboardPage extends ConsumerWidget {
  const MainDashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ProductRepository repo = ref.read(productRepositoryProvider);

    return FutureBuilder<List<Object>>(
      future: Future.wait(<Future<Object>>[
        repo.getProductList(sort: ProductSort.expiryAsc, status: 'active'),
        repo.getStatusCounts(),
      ]),
      builder: (BuildContext context, AsyncSnapshot<List<Object>> snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }

        final List<Object> results = snapshot.data ?? <Object>[];
        final List<ProductListItem> activeRows = results.isNotEmpty
            ? results[0] as List<ProductListItem>
            : <ProductListItem>[];
        final Map<String, int> counts = results.length > 1
            ? results[1] as Map<String, int>
            : <String, int>{};

        final DateTime today = DateTime.now();
        final DateTime dayStart = DateTime(today.year, today.month, today.day);

        final int expiringSoon = activeRows.where((ProductListItem item) {
          if (item.nearestExpiry == null) return false;
          final int days =
              item.nearestExpiry!.difference(dayStart).inDays;
          return days >= 0 && days <= 3;
        }).length;

        final int expired = activeRows.where((ProductListItem item) {
          if (item.nearestExpiry == null) return false;
          return item.nearestExpiry!.isBefore(dayStart);
        }).length;

        final int eatenCount = counts['eaten'] ?? 0;
        final int trashCount = counts['trash'] ?? 0;

        void navigateToProducts(String statusFilter) {
          ref.read(productStatusFilterProvider.notifier).state = statusFilter;
          context.go('/products');
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            Text(
              'main_overview_title'.tr(),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: <Widget>[
                _StatCard(
                  label: 'main_total_products'.tr(),
                  value: '${counts['active'] ?? activeRows.length}',
                  icon: Icons.inventory_2_outlined,
                  onTap: () => navigateToProducts('active'),
                ),
                _StatCard(
                  label: 'main_expiring_soon'.tr(),
                  value: '$expiringSoon',
                  icon: Icons.schedule,
                  color: expiringSoon > 0
                      ? Theme.of(context).colorScheme.errorContainer
                      : null,
                ),
                _StatCard(
                  label: 'main_expired'.tr(),
                  value: '$expired',
                  icon: Icons.warning_amber_outlined,
                  color: expired > 0
                      ? Theme.of(context).colorScheme.errorContainer
                      : null,
                ),
                _StatCard(
                  label: 'main_eaten_count'.tr(),
                  value: '$eatenCount',
                  icon: Icons.restaurant_outlined,
                  onTap: eatenCount > 0
                      ? () => navigateToProducts('eaten')
                      : null,
                ),
                _StatCard(
                  label: 'main_trash_count'.tr(),
                  value: '$trashCount',
                  icon: Icons.delete_outline,
                  onTap: trashCount > 0
                      ? () => navigateToProducts('trash')
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              'main_recent_title'.tr(),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (activeRows.isEmpty)
              Text('product_list_empty'.tr())
            else
              ...activeRows.take(6).map((ProductListItem item) {
                final DateTime? expiry = item.nearestExpiry;
                final String subtitle = expiry == null
                    ? 'product_list_days_no_date'.tr()
                    : DateFormat.yMMMd(context.locale.toString()).format(expiry);
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.inventory_2_outlined),
                    title: Text(item.product.canonicalName),
                    subtitle: Text(subtitle),
                  ),
                );
              }),
          ],
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    this.color,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      child: Card(
        color: color,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(icon),
                const SizedBox(height: 8),
                Text(
                  value,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
