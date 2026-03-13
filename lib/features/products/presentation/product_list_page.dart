import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fridgie_app/app/providers.dart';
import 'package:fridgie_app/features/products/presentation/widgets/barcode_scanner_sheet.dart';
import 'package:fridgie_app/core/db/app_database.dart';
import 'package:fridgie_app/features/categories/data/category_preset_store.dart';
import 'package:fridgie_app/features/products/data/product_repository.dart';
import 'package:fridgie_app/shared/top_snackbar.dart';
import 'package:go_router/go_router.dart';

class ProductListPage extends ConsumerStatefulWidget {
  const ProductListPage({super.key});

  @override
  ConsumerState<ProductListPage> createState() => _ProductListPageState();
}

class _ProductListPageState extends ConsumerState<ProductListPage> {
  ProductSort _sort = ProductSort.expiryAsc;
  String? _statusFilter;
  String? _categoryFilter;
  late Future<List<ProductListItem>> _listFuture;

  @override
  void initState() {
    super.initState();
    _loadSortPref();
    // One-shot: if the dashboard set a status filter, apply it immediately.
    final String? initial = ref.read(productStatusFilterProvider);
    if (initial != null) {
      _statusFilter = initial;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Clear the one-shot status filter after the first frame so we don't
        // modify providers during widget lifecycle methods (initState/build).
        if (mounted) {
          ref.read(productStatusFilterProvider.notifier).state = null;
        }
      });
    }
    _listFuture = ref.read(productRepositoryProvider).getProductList(
      sort: _sort,
      status: _statusFilter,
      category: _categoryFilter,
    );
  }

  void _refreshList() {
    _listFuture = ref.read(productRepositoryProvider).getProductList(
      sort: _sort,
      status: _statusFilter,
      category: _categoryFilter,
    );
  }

  Future<void> _loadSortPref() async {
    final AppDatabase db = ref.read(dbProvider);
    final AppSetting? row = await (db.select(db.appSettings)
          ..where((AppSettings tbl) => tbl.key.equals('default_sort')))
        .getSingleOrNull();
    if (row != null && mounted) {
      setState(() {
        _sort = _parseSortKey(row.value);
        _refreshList();
      });
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
    final productRepository = ref.read(productRepositoryProvider);
    final notificationService = ref.read(notificationServiceProvider);
    final batchRepository = ref.read(batchRepositoryProvider);

    // Delete the product first (cascade removes batches in DB).
    await productRepository.deleteProduct(item.product.id);

    // Cancel notifications in the background — don't block the delete.
    batchRepository.getBatchesByProduct(item.product.id).then((batches) {
      for (final ProductBatch batch in batches) {
        unawaited(notificationService.cancelNotification(batch.id));
      }
    }).ignore();
  }

  Future<void> _scanAndAdd() async {
    final String? scanned = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const BarcodeScannerSheet(),
    );

    if (!mounted || scanned == null || scanned.trim().isEmpty) {
      return;
    }

    final String barcode = scanned.trim();
    final DateTime now = DateTime.now();
    final DateTime scanDate = DateTime(now.year, now.month, now.day);

    final productRepository = ref.read(productRepositoryProvider);
    final batchRepository = ref.read(batchRepositoryProvider);
    final notificationService = ref.read(notificationServiceProvider);

    final Product? existingProduct = await productRepository.getByBarcode(barcode);
    if (existingProduct != null) {
      final List<ProductBatch> existingBatches = await batchRepository
          .getBatchesByProduct(existingProduct.id);

      ProductBatch? sameDayBatch;
      for (final ProductBatch batch in existingBatches) {
        final DateTime batchDay = DateTime(
          (batch.buyDate ?? batch.createdAt).year,
          (batch.buyDate ?? batch.createdAt).month,
          (batch.buyDate ?? batch.createdAt).day,
        );
        if (_isSameDay(batchDay, scanDate)) {
          sameDayBatch = batch;
          break;
        }
      }

      if (sameDayBatch != null) {
        await batchRepository.updateBatch(
          sameDayBatch.copyWith(quantity: sameDayBatch.quantity + 1),
        );
      } else {
        final ProductBatch? template =
            existingBatches.isEmpty ? null : existingBatches.last;
        final int notifDays = template?.notificationDaysBefore ?? 3;
        final String notifTime = template?.notificationTimeLocal ?? '09:00';

        final int shelfLifeDays;
        if (template == null) {
          shelfLifeDays = 7;
        } else {
          final DateTime templateBuy = template.buyDate ??
              template.expiryDate.subtract(const Duration(days: 7));
          final int diff = template.expiryDate
              .difference(DateTime(templateBuy.year, templateBuy.month, templateBuy.day))
              .inDays;
          shelfLifeDays = diff <= 0 ? 7 : diff;
        }

        final DateTime expiryDate = scanDate.add(Duration(days: shelfLifeDays));
        final int batchId = await batchRepository.createBatch(
          ProductBatchesCompanion.insert(
            productId: existingProduct.id,
            buyDate: drift.Value<DateTime>(scanDate),
            expiryDate: expiryDate,
            quantity: const drift.Value<int>(1),
            notificationDaysBefore: drift.Value<int>(notifDays),
            notificationTimeLocal: drift.Value<String>(notifTime),
          ),
        );

        unawaited(
          notificationService.scheduleExpiryNotification(
            notificationId: batchId,
            title: 'Expiry reminder',
            body: '${existingProduct.canonicalName} expires soon',
            expiryDate: expiryDate,
            daysBefore: notifDays,
            hhmm: notifTime,
          ),
        );
      }

      await productRepository.restoreActive(existingProduct.id);
      if (!mounted) return;
      showTopSnackBar(context, 'product_scan_batch_added'.tr());
      setState(_refreshList);
      return;
    }

    final String scanDateIso = scanDate.toIso8601String();
    final catalogRepo = ref.read(catalogRepositoryProvider);
    final catalogItem = await catalogRepo.getByBarcode(barcode);
    if (catalogItem != null) {
      if (!mounted) return;
      final String url =
          '/add-product?initBarcode=${Uri.encodeComponent(barcode)}&initName=${Uri.encodeComponent(catalogItem.canonicalName)}&initCategory=${Uri.encodeComponent(catalogItem.category)}&initScanDate=${Uri.encodeComponent(scanDateIso)}';
      final bool? added = await context.push<bool>(url);
      if (added == true && mounted) setState(_refreshList);
      return;
    }

    final lookupService = ref.read(productLookupServiceProvider);
    final result = await lookupService.lookupByBarcode(barcode);
    if (result != null) {
      if (!mounted) return;
      final String nameEnc = Uri.encodeComponent(result.name);
      final String categoryEnc = Uri.encodeComponent(result.category ?? '');
      final String url =
          '/add-product?initBarcode=${Uri.encodeComponent(barcode)}&initName=$nameEnc&initCategory=$categoryEnc&initScanDate=${Uri.encodeComponent(scanDateIso)}';
      final bool? added = await context.push<bool>(url);
      if (added == true && mounted) setState(_refreshList);
      return;
    }

    if (!mounted) return;
    final bool? added = await context.push<bool>(
      '/add-product?initBarcode=${Uri.encodeComponent(barcode)}&initScanDate=${Uri.encodeComponent(scanDateIso)}',
    );
    if (added == true && mounted) setState(_refreshList);
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  Future<void> _applyBatchAction(
    ProductListItem item,
    _BatchAction action,
  ) async {
    final batchRepository = ref.read(batchRepositoryProvider);
    final notificationService = ref.read(notificationServiceProvider);
    final productRepository = ref.read(productRepositoryProvider);
    final consumptionRepository = ref.read(consumptionRepositoryProvider);

    final List<ProductBatch> batches =
        await batchRepository.getBatchesByProduct(item.product.id);
    if (!mounted) {
      return;
    }

    if (batches.isEmpty) {
      showTopSnackBar(context, 'no_batches_for_product'.tr());
      return;
    }

    final List<ProductBatch> sorted = List<ProductBatch>.from(batches)
      ..sort((ProductBatch a, ProductBatch b) => a.expiryDate.compareTo(b.expiryDate));

    final ProductBatch? selected = await showDialog<ProductBatch>(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: Text(
            action == _BatchAction.eaten
                ? 'product_action_eaten'.tr()
                : 'product_action_trash'.tr(),
          ),
          content: SizedBox(
            width: 420,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: sorted.length,
                separatorBuilder: (BuildContext _, int index) =>
                  const Divider(height: 1),
              itemBuilder: (BuildContext _, int index) {
                final ProductBatch batch = sorted[index];
                final String expiry = _formatDate(batch.expiryDate);
                final String daysLeft = _daysUntilLabel(batch.expiryDate);
                return ListTile(
                  onTap: () => Navigator.of(ctx).pop(batch),
                  title: Text(
                    'add_product_batch_label'.tr(
                      namedArgs: <String, String>{'n': '${index + 1}'},
                    ),
                  ),
                  subtitle: Text(
                    'batch_expiry_with_days'.tr(
                      namedArgs: <String, String>{
                        'date': expiry,
                        'days': daysLeft,
                      },
                    ),
                  ),
                );
              },
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('confirm_cancel'.tr()),
            ),
          ],
        );
      },
    );

    if (selected == null) {
      return;
    }

    final int? consumeQuantity = await _pickConsumptionQuantity(selected);
    if (consumeQuantity == null) {
      return;
    }

    final int nextQuantity = selected.quantity - consumeQuantity;
    if (nextQuantity <= 0) {
      await batchRepository.deleteBatch(selected.id);
      unawaited(notificationService.cancelNotification(selected.id));
    } else {
      await batchRepository.updateBatch(
        selected.copyWith(quantity: nextQuantity),
      );
    }

    await consumptionRepository.logConsumption(
      productId: item.product.id,
      batchId: selected.id,
      action: action == _BatchAction.eaten ? 'eaten' : 'trash',
      quantity: consumeQuantity,
      batchExpiryDate: selected.expiryDate,
    );

    final List<ProductBatch> remaining =
        await batchRepository.getBatchesByProduct(item.product.id);
    if (remaining.isEmpty) {
      if (action == _BatchAction.eaten) {
        await productRepository.markEaten(item.product.id);
      } else {
        await productRepository.markTrash(item.product.id);
      }
    } else {
      await productRepository.restoreActive(item.product.id);
    }

    if (!mounted) {
      return;
    }

    showTopSnackBar(
      context,
      action == _BatchAction.eaten
          ? 'product_action_eaten'.tr()
          : 'product_action_trash'.tr(),
    );
    setState(_refreshList);
  }

  Future<int?> _pickConsumptionQuantity(ProductBatch selected) async {
    if (selected.quantity <= 1) {
      return 1;
    }

    int qty = 1;
    return showDialog<int>(
      context: context,
      builder: (BuildContext ctx) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setDlg) {
            return AlertDialog(
              title: Text('consume_quantity_title'.tr()),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    'consume_quantity_available'.tr(
                      namedArgs: <String, String>{
                        'count': '${selected.quantity}',
                      },
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      IconButton(
                        onPressed: qty > 1
                            ? () => setDlg(() => qty -= 1)
                            : null,
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                      Text('$qty'),
                      IconButton(
                        onPressed: qty < selected.quantity
                            ? () => setDlg(() => qty += 1)
                            : null,
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                    ],
                  ),
                ],
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text('confirm_cancel'.tr()),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(qty),
                  child: Text('confirm_ok'.tr()),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _confirmDeleteProduct(ProductListItem item) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
      title: Text('delete'.tr()),
      content: Text('delete_product_confirm'.tr()),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('confirm_cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('delete'.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    await _deleteProduct(item);
    if (mounted) {
      setState(_refreshList);
    }
  }

  Future<void> _editProduct(Product product) async {
    final bool? edited =
        await context.push<bool>('/edit-product?id=${product.id}');
    if (edited == true && mounted) setState(_refreshList);
  }

  Future<void> _openAddProduct() async {
    final bool? added = await context.push<bool>('/add-product');
    if (added == true && mounted) {
      setState(_refreshList);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('nav_products'.tr()),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          FloatingActionButton.small(
            onPressed: _scanAndAdd,
            tooltip: 'add_product_scan'.tr(),
            child: const Icon(Icons.qr_code_scanner),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            onPressed: _openAddProduct,
            icon: const Icon(Icons.add),
            label: Text('nav_add'.tr()),
          ),
        ],
      ),
      body: FutureBuilder<List<ProductListItem>>(
        future: _listFuture,
        builder: (BuildContext context, AsyncSnapshot<List<ProductListItem>> snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          final List<ProductListItem> items = snapshot.data ?? <ProductListItem>[];

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
                      onTap: () => setState(() { _statusFilter = null; _refreshList(); }),
                    ),
                    _SortChip(
                      label: 'status_active'.tr(),
                      selected: _statusFilter == 'active',
                      onTap: () => setState(() { _statusFilter = 'active'; _refreshList(); }),
                    ),
                    _SortChip(
                      label: 'status_eaten'.tr(),
                      selected: _statusFilter == 'eaten',
                      onTap: () => setState(() { _statusFilter = 'eaten'; _refreshList(); }),
                    ),
                    _SortChip(
                      label: 'status_trash'.tr(),
                      selected: _statusFilter == 'trash',
                      onTap: () => setState(() { _statusFilter = 'trash'; _refreshList(); }),
                    ),
                  ],
                ),
              ),
              // Removed top sort chips per UX update.
              Container(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: <Widget>[
                    const SizedBox(width: 48),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 5,
                      child: InkWell(
                        onTap: () {
                          // Toggle name sort
                          if (_sort == ProductSort.nameAsc) {
                            _onSortChanged(ProductSort.nameDesc);
                          } else {
                            _onSortChanged(ProductSort.nameAsc);
                          }
                        },
                        child: Row(
                          children: <Widget>[
                            Text('table_header_name'.tr(), style: Theme.of(context).textTheme.labelMedium),
                            const SizedBox(width: 6),
                            if (_sort == ProductSort.nameAsc)
                              Icon(Icons.arrow_upward, size: 16, color: Theme.of(context).textTheme.labelMedium?.color)
                            else if (_sort == ProductSort.nameDesc)
                              Icon(Icons.arrow_downward, size: 16, color: Theme.of(context).textTheme.labelMedium?.color)
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: GestureDetector(
                        onTap: () {
                          // Toggle category alphabetical sort
                          if (_sort == ProductSort.categoryAsc) {
                            _onSortChanged(ProductSort.categoryDesc);
                          } else {
                            _onSortChanged(ProductSort.categoryAsc);
                          }
                        },
                        onLongPress: () async {
                          // long-press opens category chooser
                          final List<CategoryPreset> categories = await ref.read(categoryPresetStoreProvider).getAll();
                          if (!context.mounted) {
                            return;
                          }
                          final String? choice = await showDialog<String?>(
                            context: context,
                            builder: (BuildContext ctx) {
                              return SimpleDialog(
                                title: Text('table_header_category'.tr()),
                                children: <Widget>[
                                  SimpleDialogOption(
                                    onPressed: () => Navigator.of(ctx).pop(null),
                                    child: Text('status_all'.tr()),
                                  ),
                                  ...categories.map((CategoryPreset c) => SimpleDialogOption(
                                    onPressed: () => Navigator.of(ctx).pop(c.name),
                                    child: Text(c.name),
                                  )),
                                ],
                              );
                            },
                          );
                          if (mounted) {
                            setState(() {
                              _categoryFilter = choice;
                              _refreshList();
                            });
                          }
                        },
                        child: Row(
                          children: <Widget>[
                            Text('table_header_category'.tr(), style: Theme.of(context).textTheme.labelMedium),
                            const SizedBox(width: 6),
                            if (_sort == ProductSort.categoryAsc)
                              Icon(Icons.arrow_upward, size: 16, color: Theme.of(context).textTheme.labelMedium?.color)
                            else if (_sort == ProductSort.categoryDesc)
                              Icon(Icons.arrow_downward, size: 16, color: Theme.of(context).textTheme.labelMedium?.color)
                            else if (_categoryFilter != null)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.primaryContainer,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(_categoryFilter!, style: Theme.of(context).textTheme.bodySmall),
                              ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: InkWell(
                        onTap: () {
                          // Toggle expiry sort
                          if (_sort == ProductSort.expiryAsc) {
                            _onSortChanged(ProductSort.expiryDesc);
                          } else {
                            _onSortChanged(ProductSort.expiryAsc);
                          }
                        },
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: <Widget>[
                            Text('table_header_expiry'.tr(), style: Theme.of(context).textTheme.labelMedium),
                            const SizedBox(width: 6),
                            if (_sort == ProductSort.expiryAsc)
                              Icon(Icons.arrow_upward, size: 16, color: Theme.of(context).textTheme.labelMedium?.color)
                            else if (_sort == ProductSort.expiryDesc)
                              Icon(Icons.arrow_downward, size: 16, color: Theme.of(context).textTheme.labelMedium?.color)
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(
                      width: 40,
                      child: Align(
                        alignment: Alignment.center,
                        child: Icon(Icons.edit_outlined, size: 16),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: items.isEmpty
                    ? Center(child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text('product_list_empty'.tr(), textAlign: TextAlign.center),
                      ))
                    : ListView.separated(
                        itemCount: items.length,
                        separatorBuilder: (BuildContext context, int index) =>
                            const Divider(height: 1),
                        itemBuilder: (BuildContext context, int index) {
                          final ProductListItem item = items[index];
                          final String daysLabel = _daysUntilLabel(item.nearestExpiry);

                          return Dismissible(
                            key: ValueKey<int>(item.product.id),
                            direction: DismissDirection.horizontal,
                            background: Container(
                              alignment: Alignment.centerLeft,
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              color: Colors.green,
                              child: const Icon(Icons.restaurant_menu, color: Colors.white),
                            ),
                            secondaryBackground: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              color: Theme.of(context).colorScheme.error,
                              child: Icon(
                                Icons.delete_sweep_outlined,
                                color: Theme.of(context).colorScheme.onError,
                              ),
                            ),
                            confirmDismiss: (DismissDirection direction) async {
                              if (direction == DismissDirection.startToEnd) {
                                await _applyBatchAction(item, _BatchAction.eaten);
                              } else if (direction == DismissDirection.endToStart) {
                                await _applyBatchAction(item, _BatchAction.trash);
                              }
                              return false;
                            },
                            child: InkWell(
                              onTap: () => _editProduct(item.product),
                              onLongPress: () => _confirmDeleteProduct(item),
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
                                    SizedBox(
                                      width: 40,
                                      child: IconButton(
                                        icon: const Icon(Icons.edit),
                                        onPressed: () => _editProduct(item.product),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _onSortChanged(ProductSort selected) {
    setState(() {
      _sort = selected;
      _refreshList();
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

  String _formatDate(DateTime date) {
    final DateTime local = date.toLocal();
    final String y = local.year.toString().padLeft(4, '0');
    final String m = local.month.toString().padLeft(2, '0');
    final String d = local.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}

enum _BatchAction { eaten, trash }

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
      final CategoryPreset entry = CategoryPreset(
        name: name.text.trim(),
        defaultExpiryDays: int.tryParse(days.text.trim()) ?? 7,
      );
      await ref.read(categoryPresetStoreProvider).add(entry);
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
