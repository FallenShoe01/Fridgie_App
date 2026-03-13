import 'dart:io';

import 'package:easy_localization/easy_localization.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fridgie_app/app/providers.dart';
import 'package:fridgie_app/core/db/app_database.dart';
import 'package:fridgie_app/features/products/data/product_repository.dart';
import 'package:go_router/go_router.dart';

class MainDashboardPage extends ConsumerWidget {
  const MainDashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ProductRepository repo = ref.read(productRepositoryProvider);

    final db = ref.read(dbProvider);

    return FutureBuilder<List<dynamic>>(
      future: Future.wait(<Future<dynamic>>[
        repo.getProductList(sort: ProductSort.expiryAsc, status: 'active'),
        repo.getStatusCounts(),
        (db.select(db.appSettings)
          ..where((AppSettings t) => t.key.equals('main_expiring_soon_days')))
        .getSingleOrNull(),
      ]),
      builder: (BuildContext context, AsyncSnapshot<List<dynamic>> snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }

        final List<dynamic> results = snapshot.data ?? <dynamic>[];
        final List<ProductListItem> activeRows = results.isNotEmpty
          ? results[0] as List<ProductListItem>
          : <ProductListItem>[];
        final Map<String, int> counts = results.length > 1
          ? results[1] as Map<String, int>
          : <String, int>{};

        final DateTime today = DateTime.now();
        final DateTime dayStart = DateTime(today.year, today.month, today.day);

        // Determine how many days ahead to consider "expiring soon". Default to 3.
        int expiringDays = 3;
        if (results.length > 2) {
          final AppSetting? row = results[2] as AppSetting?;
          if (row != null) {
            final int? parsed = int.tryParse(row.value);
            if (parsed != null && parsed >= 0) expiringDays = parsed;
          }
        }

        final List<ProductListItem> expiringSoonItems = activeRows.where((ProductListItem item) {
          if (item.nearestExpiry == null) return false;
          final int days = item.nearestExpiry!.difference(dayStart).inDays;
          return days >= 0 && days <= expiringDays;
        }).toList();
        

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
                  value: '${counts.values.fold<int>(0, (a, b) => a + b) == 0 ? activeRows.length : counts.values.fold<int>(0, (a, b) => a + b)}',
                  icon: Icons.inventory_2_outlined,
                  onTap: () => navigateToProducts('active'),
                  expand: true,
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              'main_expiring_soon_days'.tr(
                namedArgs: <String, String>{'days': '$expiringDays'},
              ),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (expiringSoonItems.isEmpty)
              Text('product_list_empty'.tr())
            else
              ...expiringSoonItems.take(6).map((ProductListItem item) {
                final DateTime? expiry = item.nearestExpiry;
                final int daysLeft = expiry == null ? 0 : expiry.difference(dayStart).inDays;
                final String daysText = expiry == null
                    ? ''
                    : (daysLeft < 0
                        ? '${-daysLeft} ${'product_list_days_expired'.tr()}'
                        : daysLeft == 0
                            ? 'product_list_days_today'.tr()
                            : 'product_list_days_remaining'.tr(namedArgs: <String, String>{'days': '$daysLeft'}));

                return Card(
                  child: ListTile(
                    leading: _DashImageThumb(path: item.product.defaultImagePath),
                    title: Text(item.product.canonicalName),
                    subtitle: Text(
                      expiry == null ? 'product_list_days_no_date'.tr() : DateFormat.yMMMd(context.locale.toString()).format(expiry),
                    ),
                    trailing: SizedBox(
                      width: 96,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          Text(
                            daysText.isEmpty ? '-' : daysText,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                        ],
                      ),
                    ),
                    onTap: () => context.push('/edit-product?id=${item.product.id}'),
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
    this.onTap,
    this.expand = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback? onTap;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: expand ? double.infinity : 160,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Icon(icon),
                const SizedBox(height: 8),
                Text(
                  value,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  textAlign: TextAlign.center,
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

class _DashImageThumb extends StatelessWidget {
  const _DashImageThumb({required this.path});

  final String? path;

  @override
  Widget build(BuildContext context) {
    if (path != null && path!.isNotEmpty && File(path!).existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(
          File(path!),
          height: 48,
          width: 48,
          fit: BoxFit.cover,
        ),
      );
    }

    return Container(
      height: 48,
      width: 48,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.inventory_2_outlined),
    );
  }
}
