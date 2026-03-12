import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fridgie_app/app/providers.dart';
import 'package:fridgie_app/features/products/data/product_repository.dart';

class MainDashboardPage extends ConsumerWidget {
  const MainDashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ProductRepository repo = ref.read(productRepositoryProvider);

    return FutureBuilder<List<ProductListItem>>(
      future: repo.getProductList(sort: ProductSort.expiryAsc),
      builder: (BuildContext context, AsyncSnapshot<List<ProductListItem>> snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }

        final List<ProductListItem> rows = snapshot.data ?? <ProductListItem>[];
        final DateTime today = DateTime.now();
        final DateTime dayStart = DateTime(today.year, today.month, today.day);

        final int expiringSoon = rows.where((ProductListItem item) {
          if (item.nearestExpiry == null) return false;
          final int days = item.nearestExpiry!.difference(dayStart).inDays;
          return days >= 0 && days <= 3;
        }).length;

        final int expired = rows.where((ProductListItem item) {
          if (item.nearestExpiry == null) return false;
          return item.nearestExpiry!.isBefore(dayStart);
        }).length;

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
                  value: '${rows.length}',
                  icon: Icons.inventory_2_outlined,
                ),
                _StatCard(
                  label: 'main_expiring_soon'.tr(),
                  value: '$expiringSoon',
                  icon: Icons.schedule,
                ),
                _StatCard(
                  label: 'main_expired'.tr(),
                  value: '$expired',
                  icon: Icons.warning_amber_outlined,
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              'main_recent_title'.tr(),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (rows.isEmpty)
              Text('product_list_empty'.tr())
            else
              ...rows.take(6).map((ProductListItem item) {
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
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 170,
      child: Card(
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
              Text(label),
            ],
          ),
        ),
      ),
    );
  }
}
