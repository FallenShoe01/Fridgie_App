import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fridgie_app/app/providers.dart';
import 'package:fridgie_app/core/db/app_database.dart';
import 'package:go_router/go_router.dart';

class CatalogPage extends ConsumerStatefulWidget {
  const CatalogPage({super.key});

  @override
  ConsumerState<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends ConsumerState<CatalogPage> {
  late Future<List<CatalogItem>> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(catalogRepositoryProvider).getAllCatalogItems();
  }

  Future<void> _refresh() async {
    setState(() {
      _future = ref.read(catalogRepositoryProvider).getAllCatalogItems();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('nav_catalog'.tr()),
      ),
      body: FutureBuilder<List<CatalogItem>>(
        future: _future,
        builder: (BuildContext context, AsyncSnapshot<List<CatalogItem>> snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          final List<CatalogItem> items = snapshot.data ?? <CatalogItem>[];
          if (items.isEmpty) {
            return Center(
              child: Text('catalog_empty'.tr()),
            );
          }

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              itemCount: items.length,
              separatorBuilder: (BuildContext context, int index) =>
                  const Divider(height: 1),
              itemBuilder: (BuildContext context, int index) {
                final CatalogItem item = items[index];
                return ListTile(
                  leading: _CatalogImageThumb(path: item.defaultImagePath),
                  title: Text(item.canonicalName),
                  subtitle: Text(item.category),
                  trailing: PopupMenuButton<String>(
                    onSelected: (String value) async {
                      if (value != 'edit') {
                        return;
                      }
                      final bool? changed = await context.push<bool>(
                        '/add-product?editCatalogItemId=${item.id}',
                      );
                      if (changed == true && mounted) {
                        await _refresh();
                      }
                    },
                    itemBuilder: (BuildContext context) =>
                        <PopupMenuEntry<String>>[
                      PopupMenuItem<String>(
                        value: 'edit',
                        child: Text('product_action_edit'.tr()),
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _CatalogImageThumb extends StatelessWidget {
  const _CatalogImageThumb({required this.path});

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
      child: const Icon(Icons.bookmark_outline),
    );
  }
}
