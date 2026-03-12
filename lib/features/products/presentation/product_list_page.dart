import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fridgie_app/app/providers.dart';
import 'package:fridgie_app/core/db/app_database.dart';
import 'package:fridgie_app/features/categories/data/category_preset_store.dart';
import 'package:fridgie_app/features/products/data/product_repository.dart';
import 'package:go_router/go_router.dart';

class ProductListPage extends ConsumerStatefulWidget {
  const ProductListPage({super.key});

  @override
  ConsumerState<ProductListPage> createState() => _ProductListPageState();
}

class _ProductListPageState extends ConsumerState<ProductListPage> {
  ProductSort _sort = ProductSort.expiryAsc;
  int _topViewIndex = 0;
  String? _statusFilter;

  @override
  void initState() {
    super.initState();
    _loadSortPref();
    // One-shot: if the dashboard set a status filter, apply it immediately.
    final String? initial = ref.read(productStatusFilterProvider);
    if (initial != null) {
      _statusFilter = initial;
      ref.read(productStatusFilterProvider.notifier).state = null;
    }
  }

  Future<void> _loadSortPref() async {
    final AppDatabase db = ref.read(dbProvider);
    final AppSetting? row = await (db.select(db.appSettings)
          ..where((AppSettings tbl) => tbl.key.equals('default_sort')))
        .getSingleOrNull();
    if (row != null && mounted) {
      setState(() => _sort = _parseSortKey(row.value));
    }
  }

  Future<void> _saveSortPref(ProductSort sort) async {
    final AppDatabase db = ref.read(dbProvider);
    await db.into(db.appSettings).insertOnConflictUpdate(
          AppSettingsCompanion(
            key: const drift.Value('default_sort'),
            value: drift.Value(sort.name),
          ),
        );
  }

  static ProductSort _parseSortKey(String key) {
    return ProductSort.values.firstWhere(
      (ProductSort e) => e.name == key || e.name == _legacyKey(key),
      orElse: () => ProductSort.expiryAsc,
    );
  }

  static String _legacyKey(String key) {
    const Map<String, String> map = <String, String>{
      'expiry_asc': 'expiryAsc',
      'expiry_desc': 'expiryDesc',
      'name_asc': 'nameAsc',
      'name_desc': 'nameDesc',
    };
    return map[key] ?? key;
  }

  Future<void> _deleteProduct(ProductListItem item) async {
    final batchRepository = ref.read(batchRepositoryProvider);
    final productRepository = ref.read(productRepositoryProvider);
    final notificationService = ref.read(notificationServiceProvider);

    final List<ProductBatch> batches =
        await batchRepository.getBatchesByProduct(item.product.id);
    for (final ProductBatch batch in batches) {
      await notificationService.cancelNotification(batch.id);
    }
    await productRepository.deleteProduct(item.product.id);
  }

  Future<void> _editProduct(Product product) async {
    final bool? edited =
        await context.push<bool>('/edit-product?id=${product.id}');
    if (edited == true && mounted) setState(() {});
  }

  Future<void> _markEaten(Product product) async {
    await ref.read(productRepositoryProvider).markEaten(product.id);
    if (mounted) setState(() {});
  }

  Future<void> _markTrash(Product product) async {
    await ref.read(productRepositoryProvider).markTrash(product.id);
    if (mounted) setState(() {});
  }

  Future<void> _restoreActive(Product product) async {
    await ref.read(productRepositoryProvider).restoreActive(product.id);
    if (mounted) setState(() {});
  }

  Future<void> _openAddProduct() async {
    final bool? added = await context.push<bool>('/add-product');
    if (added == true && mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final productRepository = ref.read(productRepositoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('nav_products'.tr()),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: SegmentedButton<int>(
              segments: <ButtonSegment<int>>[
                ButtonSegment<int>(
                  value: 0,
                  label: Text('nav_products'.tr()),
                ),
                ButtonSegment<int>(
                  value: 1,
                  label: Text('nav_categories'.tr()),
                ),
              ],
              selected: <int>{_topViewIndex},
              onSelectionChanged: (Set<int> values) {
                setState(() {
                  _topViewIndex = values.first;
                });
              },
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _topViewIndex == 0 ? _openAddProduct : null,
        icon: const Icon(Icons.add),
        label: Text(
          _topViewIndex == 0 ? 'nav_add'.tr() : 'category_add'.tr(),
        ),
      ),
      body: _topViewIndex == 0
          ? FutureBuilder<List<ProductListItem>>(
        future: productRepository.getProductList(
          sort: _sort,
          status: _statusFilter,
        ),
        builder: (BuildContext context, AsyncSnapshot<List<ProductListItem>> snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          final List<ProductListItem> items = snapshot.data ?? <ProductListItem>[];
          if (items.isEmpty) {
            return Center(
              child: Text('product_list_empty'.tr()),
            );
          }

          return Column(
            children: <Widget>[
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Row(
                  children: <Widget>[
                    _SortChip(
                      label: 'status_all'.tr(),
                      selected: _statusFilter == null,
                      onTap: () => setState(() => _statusFilter = null),
                    ),
                    _SortChip(
                      label: 'status_active'.tr(),
                      selected: _statusFilter == 'active',
                      onTap: () => setState(() => _statusFilter = 'active'),
                    ),
                    _SortChip(
                      label: 'status_eaten'.tr(),
                      selected: _statusFilter == 'eaten',
                      onTap: () => setState(() => _statusFilter = 'eaten'),
                    ),
                    _SortChip(
                      label: 'status_trash'.tr(),
                      selected: _statusFilter == 'trash',
                      onTap: () => setState(() => _statusFilter = 'trash'),
                    ),
                  ],
                ),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Row(
                  children: <Widget>[
                    _SortChip(
                      label: 'product_list_sort_expiry_nearest'.tr(),
                      selected: _sort == ProductSort.expiryAsc,
                      onTap: () => _onSortChanged(ProductSort.expiryAsc),
                    ),
                    _SortChip(
                      label: 'product_list_sort_expiry_latest'.tr(),
                      selected: _sort == ProductSort.expiryDesc,
                      onTap: () => _onSortChanged(ProductSort.expiryDesc),
                    ),
                    _SortChip(
                      label: 'product_list_sort_name_az'.tr(),
                      selected: _sort == ProductSort.nameAsc,
                      onTap: () => _onSortChanged(ProductSort.nameAsc),
                    ),
                    _SortChip(
                      label: 'product_list_sort_name_za'.tr(),
                      selected: _sort == ProductSort.nameDesc,
                      onTap: () => _onSortChanged(ProductSort.nameDesc),
                    ),
                  ],
                ),
              ),
              Container(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: <Widget>[
                    const SizedBox(width: 48),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 5,
                      child: Text(
                        'table_header_name'.tr(),
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        'table_header_category'.tr(),
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        'table_header_expiry'.tr(),
                        style: Theme.of(context).textTheme.labelMedium,
                        textAlign: TextAlign.end,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (BuildContext context, int index) =>
                      const Divider(height: 1),
                  itemBuilder: (BuildContext context, int index) {
                    final ProductListItem item = items[index];
                    final String daysLabel = _daysUntilLabel(item.nearestExpiry);

                    return Dismissible(
                      key: ValueKey<int>(item.product.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        color: Theme.of(context).colorScheme.error,
                        child: Icon(
                          Icons.delete_outline,
                          color: Theme.of(context).colorScheme.onError,
                        ),
                      ),
                      onDismissed: (DismissDirection direction) async {
                        await _deleteProduct(item);
                        if (mounted) setState(() {});
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Row(
                          children: <Widget>[
                            _ImageThumb(path: item.product.defaultImagePath),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 5,
                              child: Text(item.product.canonicalName),
                            ),
                            Expanded(
                              flex: 3,
                              child: Text(item.product.category),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                daysLabel,
                                textAlign: TextAlign.end,
                              ),
                            ),
                            PopupMenuButton<String>(
                              onSelected: (String value) {
                                if (value == 'edit') {
                                  _editProduct(item.product);
                                } else if (value == 'eaten') {
                                  _markEaten(item.product);
                                } else if (value == 'trash') {
                                  _markTrash(item.product);
                                } else if (value == 'restore') {
                                  _restoreActive(item.product);
                                }
                              },
                              itemBuilder: (BuildContext context) =>
                                  <PopupMenuEntry<String>>[
                                PopupMenuItem<String>(
                                  value: 'edit',
                                  child: Text('product_action_edit'.tr()),
                                ),
                                PopupMenuItem<String>(
                                  value: 'eaten',
                                  child: Text('product_action_eaten'.tr()),
                                ),
                                PopupMenuItem<String>(
                                  value: 'trash',
                                  child: Text('product_action_trash'.tr()),
                                ),
                                PopupMenuItem<String>(
                                  value: 'restore',
                                  child: Text('product_action_restore'.tr()),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      )
          : const _CategoriesManager(),
    );
  }

  void _onSortChanged(ProductSort selected) {
    setState(() {
      _sort = selected;
    });
    _saveSortPref(selected);
  }

  String _daysUntilLabel(DateTime? expiry) {
    if (expiry == null) {
      return 'product_list_days_no_date'.tr();
    }

    final DateTime now = DateTime.now();
    final int days =
        expiry.difference(DateTime(now.year, now.month, now.day)).inDays;
    if (days < 0) {
      return 'product_list_days_expired'.tr();
    }
    if (days == 0) {
      return 'product_list_days_today'.tr();
    }
    return 'product_list_days_remaining'.tr(namedArgs: <String, String>{'days': '$days'});
  }
}

class _ImageThumb extends StatelessWidget {
  const _ImageThumb({required this.path});

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

class _SortChip extends StatelessWidget {
  const _SortChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
      ),
    );
  }
}

class _CategoriesManager extends ConsumerStatefulWidget {
  const _CategoriesManager();

  @override
  ConsumerState<_CategoriesManager> createState() => _CategoriesManagerState();
}

class _CategoriesManagerState extends ConsumerState<_CategoriesManager> {
  late Future<List<CategoryPreset>> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(categoryPresetStoreProvider).getAll();
  }

  Future<void> _refresh() async {
    setState(() {
      _future = ref.read(categoryPresetStoreProvider).getAll();
    });
  }

  Future<void> _deleteCategory(CategoryPreset item) async {
    await ref.read(categoryPresetStoreProvider).deleteByName(item.name);
    await _refresh();
  }

  Future<void> _addCategory() async {
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
                decoration: InputDecoration(labelText: 'table_header_name'.tr()),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: days,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: 'category_default_days'.tr()),
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
      final List<CategoryPreset> current =
          await ref.read(categoryPresetStoreProvider).getAll();
      current.removeWhere(
        (CategoryPreset item) =>
            item.name.toLowerCase() == name.text.trim().toLowerCase(),
      );
      current.add(
        CategoryPreset(
          name: name.text.trim(),
          defaultExpiryDays: int.tryParse(days.text.trim()) ?? 7,
        ),
      );
      await ref.read(categoryPresetStoreProvider).saveAll(current);
      await _refresh();
    }

    name.dispose();
    days.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<CategoryPreset>>(
      future: _future,
      builder: (BuildContext context, AsyncSnapshot<List<CategoryPreset>> snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final List<CategoryPreset> categories = snapshot.data ?? <CategoryPreset>[];
        return Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: _addCategory,
                  icon: const Icon(Icons.add),
                  label: Text('category_add'.tr()),
                ),
              ),
            ),
            if (categories.isEmpty)
              Expanded(child: Center(child: Text('category_empty'.tr())))
            else
              Expanded(
                child: ListView.separated(
                  itemCount: categories.length,
                  separatorBuilder: (BuildContext context, int index) =>
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
                        onPressed: () => _deleteCategory(item),
                      ),
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}
