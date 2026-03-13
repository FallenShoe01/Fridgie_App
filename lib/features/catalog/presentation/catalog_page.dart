import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fridgie_app/app/providers.dart';
import 'package:fridgie_app/core/db/app_database.dart';
import 'package:go_router/go_router.dart';
import 'package:fridgie_app/features/categories/data/category_preset_store.dart';
import 'package:fridgie_app/features/products/data/product_repository.dart';

class CatalogPage extends ConsumerStatefulWidget {
  const CatalogPage({super.key});

  @override
  ConsumerState<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends ConsumerState<CatalogPage> {
  late Future<List<CatalogItem>> _future;
  int _viewIndex = 0; // 0 = catalog items, 1 = categories
  ProductSort _sort = ProductSort.nameAsc;

  Future<void> _showAddCategoryDialog() async {
    final TextEditingController name = TextEditingController();
    final TextEditingController days = TextEditingController(text: '7');
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('category_add'.tr()),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                controller: name,
                decoration: InputDecoration(
                  labelText: 'table_header_name'.tr(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: days,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'category_default_days'.tr(),
                ),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('confirm_cancel'.tr()),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text('confirm_ok'.tr()),
            ),
          ],
        );
      },
    );
    if (ok == true) {
      final CategoryPreset entry = CategoryPreset(
        name: name.text.trim(),
        defaultExpiryDays: int.tryParse(days.text.trim()) ?? 7,
      );
      await ref.read(categoryPresetStoreProvider).add(entry);
      setState(() {});
    }
    name.dispose();
    days.dispose();
  }

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
      appBar: AppBar(title: Text('nav_catalog'.tr())),
      body: Stack(
        children: <Widget>[
          if (_viewIndex == 0)
            FutureBuilder<List<CatalogItem>>(
              future: _future,
              builder:
                  (
                    BuildContext context,
                    AsyncSnapshot<List<CatalogItem>> snapshot,
                  ) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final List<CatalogItem> items = List<CatalogItem>.from(
                      snapshot.data ?? <CatalogItem>[],
                    );
                    // apply header sort options
                    switch (_sort) {
                      case ProductSort.nameAsc:
                        items.sort(
                          (a, b) => a.canonicalName.compareTo(b.canonicalName),
                        );
                        break;
                      case ProductSort.nameDesc:
                        items.sort(
                          (a, b) => b.canonicalName.compareTo(a.canonicalName),
                        );
                        break;
                      case ProductSort.categoryAsc:
                        items.sort((a, b) => a.category.compareTo(b.category));
                        break;
                      case ProductSort.categoryDesc:
                        items.sort((a, b) => b.category.compareTo(a.category));
                        break;
                      default:
                        break;
                    }
                    if (items.isEmpty) {
                      return Center(child: Text('catalog_empty'.tr()));
                    }

                    return Column(
                      children: <Widget>[
                        Container(
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerLow,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          child: Row(
                            children: <Widget>[
                              const SizedBox(width: 48),
                              const SizedBox(width: 12),
                              Expanded(
                                flex: 5,
                                child: InkWell(
                                  onTap: () {
                                    if (_sort == ProductSort.nameAsc) {
                                      setState(() {
                                        _sort = ProductSort.nameDesc;
                                      });
                                    } else {
                                      setState(() {
                                        _sort = ProductSort.nameAsc;
                                      });
                                    }
                                  },
                                  child: Row(
                                    children: <Widget>[
                                      Text(
                                        'table_header_name'.tr(),
                                        style: Theme.of(
                                          context,
                                        ).textTheme.labelMedium,
                                      ),
                                      const SizedBox(width: 6),
                                      if (_sort == ProductSort.nameAsc)
                                        Icon(
                                          Icons.arrow_upward,
                                          size: 16,
                                          color: Theme.of(
                                            context,
                                          ).textTheme.labelMedium?.color,
                                        )
                                      else if (_sort == ProductSort.nameDesc)
                                        Icon(
                                          Icons.arrow_downward,
                                          size: 16,
                                          color: Theme.of(
                                            context,
                                          ).textTheme.labelMedium?.color,
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 3,
                                child: InkWell(
                                  onTap: () {
                                    if (_sort == ProductSort.categoryAsc) {
                                      setState(() {
                                        _sort = ProductSort.categoryDesc;
                                      });
                                    } else {
                                      setState(() {
                                        _sort = ProductSort.categoryAsc;
                                      });
                                    }
                                  },
                                  child: Row(
                                    children: <Widget>[
                                      Text(
                                        'table_header_category'.tr(),
                                        style: Theme.of(
                                          context,
                                        ).textTheme.labelMedium,
                                      ),
                                      const SizedBox(width: 6),
                                      if (_sort == ProductSort.categoryAsc)
                                        Icon(
                                          Icons.arrow_upward,
                                          size: 16,
                                          color: Theme.of(
                                            context,
                                          ).textTheme.labelMedium?.color,
                                        )
                                      else if (_sort ==
                                          ProductSort.categoryDesc)
                                        Icon(
                                          Icons.arrow_downward,
                                          size: 16,
                                          color: Theme.of(
                                            context,
                                          ).textTheme.labelMedium?.color,
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                              const Expanded(flex: 2, child: SizedBox()),
                            ],
                          ),
                        ),
                        Expanded(
                          child: RefreshIndicator(
                            onRefresh: _refresh,
                            child: ListView.separated(
                              itemCount: items.length,
                              separatorBuilder:
                                  (BuildContext context, int index) =>
                                      const Divider(height: 1),
                              itemBuilder: (BuildContext context, int index) {
                                final CatalogItem item = items[index];
                                return InkWell(
                                  onTap: () async {
                                    final bool?
                                    changed = await context.push<bool>(
                                      '/add-product?editCatalogItemId=${item.id}',
                                    );
                                    if (changed == true && mounted) {
                                      await _refresh();
                                    }
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    child: Row(
                                      children: <Widget>[
                                        _CatalogImageThumb(
                                          path: item.defaultImagePath,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          flex: 5,
                                          child: Text(
                                            item.canonicalName,
                                            style: Theme.of(
                                              context,
                                            ).textTheme.bodyMedium,
                                          ),
                                        ),
                                        Expanded(
                                          flex: 3,
                                          child: Text(
                                            item.category,
                                            style: Theme.of(
                                              context,
                                            ).textTheme.bodySmall,
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.edit),
                                          onPressed: () async {
                                            final bool?
                                            changed = await context.push<bool>(
                                              '/add-product?editCatalogItemId=${item.id}',
                                            );
                                            if (changed == true && mounted) {
                                              await _refresh();
                                            }
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    );
                  },
            )
          else
            FutureBuilder<List<CategoryPreset>>(
              future: ref.read(categoryPresetStoreProvider).getAll(),
              builder:
                  (
                    BuildContext context,
                    AsyncSnapshot<List<CategoryPreset>> snapshot,
                  ) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final List<CategoryPreset> categories =
                        snapshot.data ?? <CategoryPreset>[];
                    return Column(
                      children: <Widget>[
                        const SizedBox(height: 12),
                        if (categories.isEmpty)
                          Expanded(
                            child: Center(child: Text('category_empty'.tr())),
                          )
                        else
                          Expanded(
                            child: ListView.separated(
                              itemCount: categories.length,
                              separatorBuilder:
                                  (BuildContext context, int index) =>
                                      const Divider(height: 1),
                              itemBuilder: (BuildContext context, int index) {
                                final CategoryPreset item = categories[index];
                                return ListTile(
                                  title: Text(item.name),
                                  subtitle: Text(
                                    'category_default_days_value'.tr(
                                      namedArgs: <String, String>{
                                        'days': '${item.defaultExpiryDays}',
                                      },
                                    ),
                                  ),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.delete_outline),
                                    onPressed: () async {
                                      await ref
                                          .read(categoryPresetStoreProvider)
                                          .deleteByName(item.name);
                                      setState(() {});
                                    },
                                  ),
                                );
                              },
                            ),
                          ),
                      ],
                    );
                  },
            ),
          Positioned(
            left: 18,
            bottom: 18,
            child: FloatingActionButton(
              onPressed: () => setState(() {
                _viewIndex = (_viewIndex == 0) ? 1 : 0;
              }),
              tooltip: _viewIndex == 0
                  ? 'nav_categories'.tr()
                  : 'nav_catalog'.tr(),
              child: Icon(_viewIndex == 0 ? Icons.category : Icons.list),
            ),
          ),
          Positioned(
            right: 18,
            bottom: 18,
            child: _viewIndex == 1
                ? FloatingActionButton(
                    onPressed: _showAddCategoryDialog,
                    tooltip: 'category_add'.tr(),
                    child: const Icon(Icons.add),
                  )
                : FloatingActionButton.extended(
                    onPressed: () async {
                      final bool? added = await context.push<bool>(
                        '/add-product?catalogOnly=1',
                      );
                      if (added == true && mounted) {
                        setState(() {
                          _future = ref
                              .read(catalogRepositoryProvider)
                              .getAllCatalogItems();
                        });
                      }
                    },
                    icon: const Icon(Icons.add),
                    label: Text('nav_add'.tr()),
                    tooltip: 'nav_add'.tr(),
                  ),
          ),
        ],
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
