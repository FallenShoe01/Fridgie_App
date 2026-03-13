import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fridgie_app/app/providers.dart';
import 'package:fridgie_app/core/db/app_database.dart';
import 'package:fridgie_app/features/categories/data/category_preset_store.dart';
import 'package:fridgie_app/features/lookup/data/models/lookup_result.dart';
import 'package:fridgie_app/features/products/presentation/widgets/barcode_scanner_sheet.dart';
import 'package:fridgie_app/features/products/presentation/widgets/product_autocomplete_field.dart';
import 'package:image_picker/image_picker.dart';
import 'package:fridgie_app/shared/top_snackbar.dart';

class AddProductPage extends ConsumerStatefulWidget {
  const AddProductPage({
    super.key,
    this.editProductId,
    this.editCatalogItemId,
    this.catalogOnlyAdd = false,
    this.initialBarcode,
    this.initialName,
    this.initialCategory,
    this.initialScanDate,
  });

  final String? initialBarcode;
  final String? initialName;
  final String? initialCategory;
  final String? initialScanDate;

  final int? editProductId;
  final int? editCatalogItemId;
  final bool catalogOnlyAdd;

  @override
  ConsumerState<AddProductPage> createState() => _AddProductPageState();
}

class _AddProductPageState extends ConsumerState<AddProductPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _nameFieldKey = GlobalKey();
  final GlobalKey _categoryFieldKey = GlobalKey();
  DateTime? _lastAutoScrollAt;
  bool _isAutoScrollRunning = false;

  final TextEditingController _barcodeController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _categoryController = TextEditingController();
  final List<_DraftBatch> _batches = <_DraftBatch>[
    _DraftBatch(
      quantity: 1,
      buyDate: DateTime.now(),
      expiryDate: DateTime.now().add(const Duration(days: 7)),
    ),
  ];

  bool _isLoadingLookup = false;
  bool _isSaving = false;
  bool _isLoadingInitialData = false;
  String? _localImagePath;
  List<CategoryPreset> _categoryPresets = <CategoryPreset>[];
  int _settingsDefaultNotificationDaysBefore = 3;
  String _settingsDefaultNotificationTime = '09:00';
  Product? _editingProduct;
  CatalogItem? _editingCatalogItem;
  List<ConsumptionEvent> _consumptionHistory = <ConsumptionEvent>[];

  int _defaultCategoryDays() {
    if (_batches.isEmpty) {
      return 7;
    }

    final _DraftBatch batch = _batches.first;
    final int days = batch.expiryDate.difference(batch.buyDate).inDays;
    return days <= 0 ? 7 : days;
  }

  Future<void> _ensureCategoryExists(String category) async {
    final String normalized = category.trim();
    if (normalized.isEmpty || normalized == 'unknown') {
      return;
    }

    await ref
        .read(categoryPresetStoreProvider)
        .add(
          CategoryPreset(
            name: normalized,
            defaultExpiryDays: _defaultCategoryDays(),
          ),
        );

    if (!mounted) {
      return;
    }

    final List<CategoryPreset> presets = await ref
        .read(categoryPresetStoreProvider)
        .getAll();
    if (!mounted) {
      return;
    }
    setState(() {
      _categoryPresets = presets;
    });
  }

  @override
  void initState() {
    super.initState();
    _loadBatchDefaultsFromSettings();
    _loadCategoryPresets();
    _loadInitialDataForEdit();
    if (!_isEditMode) {
      if (widget.initialBarcode != null && widget.initialBarcode!.isNotEmpty) {
        _barcodeController.text = widget.initialBarcode!;
      }
      if (widget.initialName != null && widget.initialName!.isNotEmpty) {
        try {
          _nameController.text = Uri.decodeComponent(widget.initialName!);
        } catch (_) {
          _nameController.text = widget.initialName!;
        }
      }
      if (widget.initialCategory != null && widget.initialCategory!.isNotEmpty) {
        try {
          _categoryController.text = Uri.decodeComponent(widget.initialCategory!);
        } catch (_) {
          _categoryController.text = widget.initialCategory!;
        }
        _applyCategoryPresetIfExists(_categoryController.text);
      }
      if (widget.initialScanDate != null && widget.initialScanDate!.isNotEmpty) {
        try {
          final DateTime parsed = DateTime.parse(widget.initialScanDate!);
          final DateTime day = DateTime(parsed.year, parsed.month, parsed.day);
          if (_batches.isNotEmpty) {
            final _DraftBatch first = _batches.first;
            _batches[0] = first.copyWith(
              buyDate: day,
              expiryDate: day.add(const Duration(days: 7)),
            );
          }
        } catch (_) {
          // Ignore invalid date payload.
        }
      }
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _barcodeController.dispose();
    _nameController.dispose();
    _categoryController.dispose();
    super.dispose();
  }

  void _ensureAutocompleteVisible(GlobalKey key) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        return;
      }
      final DateTime now = DateTime.now();
      if (_isAutoScrollRunning) {
        return;
      }
      if (_lastAutoScrollAt != null &&
          now.difference(_lastAutoScrollAt!).inMilliseconds < 260) {
        return;
      }

      final BuildContext? targetContext = key.currentContext;
      if (targetContext == null) {
        return;
      }

      _isAutoScrollRunning = true;
      _lastAutoScrollAt = now;
      try {
        await Scrollable.ensureVisible(
          targetContext,
          alignment: 0.14,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
        );
      } finally {
        _isAutoScrollRunning = false;
      }
    });
  }

  Future<List<CatalogItem>> _searchNameSuggestions(String query) async {
    final String normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return <CatalogItem>[];
    }

    final Map<String, CatalogItem> merged = <String, CatalogItem>{};

    final catalogResults = await ref
        .read(catalogRepositoryProvider)
        .autocompleteByName(query);

    for (final CatalogItem item in catalogResults) {
      merged[item.canonicalName.trim().toLowerCase()] = item;
    }

    if (merged.isEmpty) {
      final List<CatalogItem> allCatalog = await ref
          .read(catalogRepositoryProvider)
          .getAllCatalogItems();
      for (final CatalogItem item in allCatalog) {
        if (item.canonicalName.toLowerCase().contains(normalized)) {
          merged[item.canonicalName.trim().toLowerCase()] = item;
        }
      }
    }

    final productResults = await ref
        .read(productRepositoryProvider)
        .autocompleteByName(query);

    for (final Product p in productResults) {
      final CatalogItem mapped = CatalogItem(
        id: p.id,
        canonicalName: p.canonicalName,
        barcode: p.barcode,
        category: p.category,
        defaultImagePath: p.defaultImagePath,
        createdAt: p.createdAt,
        updatedAt: p.updatedAt,
      );
      merged.putIfAbsent(p.canonicalName.trim().toLowerCase(), () => mapped);
    }

    final List<CatalogItem> output = merged.values.toList(growable: false)
      ..sort((CatalogItem a, CatalogItem b) => a.canonicalName.compareTo(b.canonicalName));

    return output.take(10).toList(growable: false);
  }

  Future<void> _loadCategoryPresets() async {
    final List<CategoryPreset> presets = await ref
        .read(categoryPresetStoreProvider)
        .getAll();
    if (!mounted) {
      return;
    }
    setState(() {
      _categoryPresets = presets;
    });

    if (!_isEditMode) {
      _applyCategoryPresetIfExists(_categoryController.text);
    }
  }

  Future<void> _loadBatchDefaultsFromSettings() async {
    final AppDatabase db = ref.read(dbProvider);
    final List<AppSetting> rows = await db.select(db.appSettings).get();
    final Map<String, String> map = <String, String>{
      for (final AppSetting row in rows) row.key: row.value,
    };

    final int notifDays =
        int.tryParse(map['default_notification_days_before'] ?? '') ?? 3;
    final String notifTimeRaw = map['default_notification_time_local'] ?? '09:00';
    if (!mounted) {
      return;
    }

    setState(() {
      _settingsDefaultNotificationDaysBefore = notifDays.clamp(0, 365);
      _settingsDefaultNotificationTime = _normalizeTime(notifTimeRaw);

      if (!_isEditMode && _batches.isNotEmpty) {
        final _DraftBatch first = _batches.first;
        _batches[0] = first.copyWith(
          notifDaysBefore: _settingsDefaultNotificationDaysBefore,
          notifTime: _settingsDefaultNotificationTime,
        );
      }
    });
  }

  String _normalizeTime(String raw) {
    final List<String> parts = raw.split(':');
    if (parts.length != 2) {
      return '09:00';
    }
    final int? h = int.tryParse(parts[0]);
    final int? m = int.tryParse(parts[1]);
    if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) {
      return '09:00';
    }
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  CategoryPreset? _findCategoryPresetByName(String categoryName) {
    final String normalized = categoryName.trim().toLowerCase();
    if (normalized.isEmpty) {
      return null;
    }

    for (final CategoryPreset preset in _categoryPresets) {
      if (preset.name.trim().toLowerCase() == normalized) {
        return preset;
      }
    }
    return null;
  }

  int _effectiveNotifDaysForCategory(String categoryName) {
    final CategoryPreset? preset = _findCategoryPresetByName(categoryName);
    return preset?.defaultExpiryDays ?? _settingsDefaultNotificationDaysBefore;
  }

  void _overwriteBatchNotifDaysForCategory(String categoryName) {
    final int notifDays = _effectiveNotifDaysForCategory(categoryName);
    setState(() {
      _batches.setAll(
        0,
        _batches.map(
          (_DraftBatch batch) => batch.copyWith(
            notifDaysBefore: notifDays,
          ),
        ),
      );
    });
  }

  void _applyCategoryPresetIfExists(String categoryName) {
    _overwriteBatchNotifDaysForCategory(categoryName);
  }

  void _addBatchWithDefaults() {
    final DateTime buyDate = DateTime.now();

    setState(() {
      _batches.add(
        _DraftBatch(
          quantity: 1,
          buyDate: buyDate,
          expiryDate: buyDate.add(const Duration(days: 7)),
          notifDaysBefore: _settingsDefaultNotificationDaysBefore,
          notifTime: _settingsDefaultNotificationTime,
        ),
      );
    });
  }

  bool get _isEditMode =>
      widget.editProductId != null || widget.editCatalogItemId != null;

  bool get _isCatalogOnlyEdit =>
      widget.catalogOnlyAdd == true ||
      (widget.editCatalogItemId != null && widget.editProductId == null);

  Future<void> _loadInitialDataForEdit() async {
    if (!_isEditMode) {
      return;
    }

    setState(() {
      _isLoadingInitialData = true;
    });

    if (widget.editProductId != null) {
      final int productId = widget.editProductId!;
      final AppDatabase db = ref.read(dbProvider);

      final Product? product = await (db.select(
        db.products,
      )..where((Products t) => t.id.equals(productId))).getSingleOrNull();
      final List<ProductBatch> batches = await ref
          .read(batchRepositoryProvider)
          .getBatchesByProduct(productId);
        final List<ConsumptionEvent> history = await ref
          .read(consumptionRepositoryProvider)
          .getByProduct(productId);

      if (!mounted) {
        return;
      }

      if (product != null) {
        _editingProduct = product;
        _barcodeController.text = product.barcode ?? '';
        _nameController.text = product.canonicalName;
        _categoryController.text = product.category;
        _localImagePath = product.defaultImagePath;

        _batches
          ..clear()
          ..addAll(
            batches.isEmpty
                ? <_DraftBatch>[
                    _DraftBatch(
                      quantity: 1,
                      buyDate: DateTime.now(),
                      expiryDate: DateTime.now().add(const Duration(days: 7)),
                    ),
                  ]
                : batches
                      .map(
                        (ProductBatch b) => _DraftBatch(
                          quantity: b.quantity,
                          buyDate: b.buyDate ?? DateTime.now(),
                          expiryDate: b.expiryDate,
                          notifDaysBefore: b.notificationDaysBefore,
                          notifTime: b.notificationTimeLocal,
                        ),
                      )
                      .toList(growable: false),
          );
                _consumptionHistory = history;
      }
    } else if (widget.editCatalogItemId != null) {
      _consumptionHistory = <ConsumptionEvent>[];
      final CatalogItem? item = await ref
          .read(catalogRepositoryProvider)
          .getById(widget.editCatalogItemId!);

      if (!mounted) {
        return;
      }

      if (item != null) {
        _editingCatalogItem = item;
        _barcodeController.text = item.barcode ?? '';
        _nameController.text = item.canonicalName;
        _categoryController.text = item.category;
        _localImagePath = item.defaultImagePath;
      }
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _isLoadingInitialData = false;
    });
  }

  void _applyCategoryPreset(CategoryPreset preset) {
    _categoryController.text = preset.name;
    _overwriteBatchNotifDaysForCategory(preset.name);
  }

  Future<void> _scanBarcode() async {
    final String? scanned = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const BarcodeScannerSheet(),
    );

    if (!mounted || scanned == null || scanned.trim().isEmpty) {
      return;
    }

    _barcodeController.text = scanned.trim();
    await _lookupFromBarcode();
  }

  Future<void> _lookupFromBarcode() async {
    final String barcode = _barcodeController.text.trim();
    if (barcode.isEmpty) {
      return;
    }

    setState(() {
      _isLoadingLookup = true;
    });

    final lookupService = ref.read(productLookupServiceProvider);
    final imageService = ref.read(imageServiceProvider);

    // First: check local catalog by barcode
    final catalogRepo = ref.read(catalogRepositoryProvider);
    final CatalogItem? catalogItem = await catalogRepo.getByBarcode(barcode);

    if (!mounted) return;

    if (catalogItem != null) {
      _nameController.text = catalogItem.canonicalName;
      _categoryController.text = catalogItem.category.trim();
      _applyCategoryPresetIfExists(_categoryController.text);

      if ((catalogItem.defaultImagePath ?? '').isNotEmpty) {
        setState(() {
          _localImagePath = catalogItem.defaultImagePath;
        });
      }

      showTopSnackBar(context, 'add_product_found_local'.tr());
      setState(() {
        _isLoadingLookup = false;
      });
      return;
    }

    // Fallback: world lookup providers
    final LookupResult? result = await lookupService.lookupByBarcode(barcode);

    if (!mounted) {
      return;
    }

    if (result != null) {
      _nameController.text = result.name;
      _categoryController.text = (result.category ?? '').trim();
      _applyCategoryPresetIfExists(_categoryController.text);

      if ((result.imageUrl ?? '').isNotEmpty) {
        final String? downloadedPath = await imageService.downloadAndStoreImage(
          imageUrl: result.imageUrl!,
          imageKey: barcode,
        );

        if (!mounted) {
          return;
        }

        if (downloadedPath != null) {
          setState(() {
            _localImagePath = downloadedPath;
          });
        }
      }

      showTopSnackBar(context, 'add_product_found'.tr());
    } else {
      showTopSnackBar(context, 'add_product_not_found'.tr());
    }

    setState(() {
      _isLoadingLookup = false;
    });
  }

  Future<void> _pickImage(ImageSource source) async {
    final imageService = ref.read(imageServiceProvider);
    final String key = _barcodeController.text.trim().isEmpty
        ? _nameController.text.trim()
        : _barcodeController.text.trim();

    final String? imagePath = await imageService.pickCropAndStoreImage(
      context: context,
      imageKey: key,
      source: source,
    );

    if (!mounted || imagePath == null) {
      return;
    }

    setState(() {
      _localImagePath = imagePath;
    });
  }

  Future<void> _pickDate({required int index, required bool isExpiry}) async {
    final _DraftBatch batch = _batches[index];
    final DateTime initial = isExpiry ? batch.expiryDate : batch.buyDate;

    final DateTime? selected = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

    if (!mounted || selected == null) {
      return;
    }

    setState(() {
      if (isExpiry) {
        _batches[index] = batch.copyWith(expiryDate: selected);
      } else {
        _batches[index] = batch.copyWith(buyDate: selected);
      }
    });
  }

  void _changeNotifDays(int index, int delta) {
    final _DraftBatch current = _batches[index];
    final int next = (current.notifDaysBefore + delta).clamp(0, 365);
    setState(() {
      _batches[index] = current.copyWith(notifDaysBefore: next);
    });
  }

  Future<void> _pickNotifTime(int index) async {
    final _DraftBatch batch = _batches[index];
    final List<String> parts = batch.notifTime.split(':');
    final int h = int.tryParse(parts.isNotEmpty ? parts[0] : '9') ?? 9;
    final int m = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: h, minute: m),
    );
    if (!mounted || picked == null) return;
    final String formatted =
        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    setState(() {
      _batches[index] = batch.copyWith(notifTime: formatted);
    });
  }

  void _duplicateBatch(int index) {
    setState(() {
      _batches.insert(index + 1, _batches[index].copyWith());
    });
  }

  void _removeBatch(int index) {
    if (_batches.length == 1) {
      return;
    }
    setState(() {
      _batches.removeAt(index);
    });
  }

  void _changeQuantity(int index, int delta) {
    final _DraftBatch current = _batches[index];
    final int nextValue = (current.quantity + delta).clamp(1, 9999);
    setState(() {
      _batches[index] = current.copyWith(quantity: nextValue);
    });
  }

  Future<void> _save() async {
    FocusManager.instance.primaryFocus?.unfocus();

    if (!_formKey.currentState!.validate()) {
      return;
    }

    final String name = _nameController.text.trim();
    if (name.isEmpty) {
      showTopSnackBar(context, 'add_product_name_required'.tr());
      return;
    }

    setState(() {
      _isSaving = true;
    });

    final AppDatabase db = ref.read(dbProvider);
    final productRepository = ref.read(productRepositoryProvider);
    final catalogRepository = ref.read(catalogRepositoryProvider);
    final batchRepository = ref.read(batchRepositoryProvider);
    final notificationService = ref.read(notificationServiceProvider);

    final String barcode = _barcodeController.text.trim();
    final String category = _categoryController.text.trim().isEmpty
        ? 'unknown'
        : _categoryController.text.trim();
    await _ensureCategoryExists(category);

    // If this page was opened for "catalog-only" creation (no Product),
    // create or update the CatalogItem and return immediately.
    if (widget.catalogOnlyAdd && _editingCatalogItem == null) {
      await catalogRepository.upsertCatalogItem(
        canonicalName: name,
        barcode: barcode,
        category: category,
        defaultImagePath: _localImagePath,
      );

      if (!mounted) return;
      setState(() {
        _isSaving = false;
      });
      Navigator.of(context).pop(true);
      return;
    }
    if (_isCatalogOnlyEdit && _editingCatalogItem != null) {
      await catalogRepository.updateCatalogItem(
        _editingCatalogItem!,
        canonicalName: name,
        barcode: barcode,
        category: category,
        defaultImagePath: _localImagePath,
      );
    } else if (_editingProduct != null) {
      await productRepository.updateProduct(
        _editingProduct!.copyWith(
          canonicalName: name,
          barcode: drift.Value<String?>(barcode.isEmpty ? null : barcode),
          category: category,
          defaultImagePath: drift.Value<String?>(_localImagePath),
          status: 'active',
          statusUpdatedAt: drift.Value<DateTime?>(DateTime.now()),
          updatedAt: DateTime.now(),
        ),
      );

      await catalogRepository.upsertCatalogItem(
        canonicalName: name,
        barcode: barcode,
        category: category,
        defaultImagePath: _localImagePath,
      );

      // Product edit supports batch editing: replace existing batches with draft rows.
      final List<ProductBatch> existingBatches = await batchRepository
          .getBatchesByProduct(_editingProduct!.id);
      for (final ProductBatch existing in existingBatches) {
        await batchRepository.deleteBatch(existing.id);
        unawaited(notificationService.cancelNotification(existing.id));
      }

      for (final _DraftBatch batch in _batches) {
        final int batchId = await batchRepository.createBatch(
          ProductBatchesCompanion.insert(
            productId: _editingProduct!.id,
            buyDate: drift.Value(batch.buyDate),
            expiryDate: batch.expiryDate,
            quantity: drift.Value(batch.quantity),
            notificationDaysBefore: drift.Value(batch.notifDaysBefore),
            notificationTimeLocal: drift.Value(batch.notifTime),
          ),
        );

        unawaited(
          notificationService.scheduleExpiryNotification(
            notificationId: batchId,
            title: 'Expiry reminder',
            body: '$name expires soon',
            expiryDate: batch.expiryDate,
            daysBefore: batch.notifDaysBefore,
            hhmm: batch.notifTime,
          ),
        );
      }
    } else {
      final int productId = await productRepository.createProduct(
        ProductsCompanion.insert(
          canonicalName: name,
          barcode: barcode.isEmpty
              ? const drift.Value.absent()
              : drift.Value(barcode),
          category: drift.Value(category),
          defaultImagePath: _localImagePath == null
              ? const drift.Value.absent()
              : drift.Value(_localImagePath),
          source: drift.Value(barcode.isEmpty ? 'manual' : 'lookup_or_manual'),
        ),
      );

      await catalogRepository.upsertCatalogItem(
        canonicalName: name,
        barcode: barcode,
        category: category,
        defaultImagePath: _localImagePath,
      );

      for (final _DraftBatch batch in _batches) {
        final int batchId = await batchRepository.createBatch(
          ProductBatchesCompanion.insert(
            productId: productId,
            buyDate: drift.Value(batch.buyDate),
            expiryDate: batch.expiryDate,
            quantity: drift.Value(batch.quantity),
            notificationDaysBefore: drift.Value(batch.notifDaysBefore),
            notificationTimeLocal: drift.Value(batch.notifTime),
          ),
        );

        unawaited(
          notificationService.scheduleExpiryNotification(
            notificationId: batchId,
            title: 'Expiry reminder',
            body: '$name expires soon',
            expiryDate: batch.expiryDate,
            daysBefore: batch.notifDaysBefore,
            hhmm: batch.notifTime,
          ),
        );
      }

      if (_localImagePath != null) {
        await db
            .into(db.productImages)
            .insert(
              ProductImagesCompanion.insert(
                productId: productId,
                barcode: barcode.isEmpty
                    ? const drift.Value.absent()
                    : drift.Value(barcode),
                localPath: _localImagePath!,
              ),
            );
      }
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _isSaving = false;
    });

    Navigator.of(context).pop(true);
  }

  Future<void> _confirmAndDeleteCatalogItem() async {
    if (_editingCatalogItem == null) return;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text('delete'.tr()),
        content: Text('delete_catalog_confirm'.tr()),
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

    if (confirmed != true) return;

    final catalogRepository = ref.read(catalogRepositoryProvider);
    await catalogRepository.deleteById(_editingCatalogItem!.id);

    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingInitialData) {
      return Scaffold(
        appBar: AppBar(title: Text('product_action_edit'.tr())),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final double textScale = MediaQuery.textScalerOf(
      context,
    ).scale(1).clamp(1, 1.25);
    final double previewSize = MediaQuery.sizeOf(context).width * 0.4;
    final double keyboardInset = MediaQuery.viewInsetsOf(context).bottom;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: Text(
          _isEditMode ? 'product_action_edit'.tr() : 'add_product_title'.tr(),
        ),
      ),
      body: Stack(
        children: <Widget>[
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
            child: SingleChildScrollView(
              controller: _scrollController,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 170),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                  Align(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: _localImagePath != null
                          ? Image.file(
                              File(_localImagePath!),
                              height: previewSize,
                              width: previewSize,
                              fit: BoxFit.cover,
                            )
                          : Container(
                              height: previewSize,
                              width: previewSize,
                              color: Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest,
                              alignment: Alignment.center,
                              child: Icon(
                                Icons.photo_outlined,
                                size: 42,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Center(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: <Widget>[
                        OutlinedButton.icon(
                          onPressed: () => _pickImage(ImageSource.gallery),
                          icon: const Icon(Icons.photo_library_outlined),
                          label: Text('add_product_gallery'.tr()),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _pickImage(ImageSource.camera),
                          icon: const Icon(Icons.camera_alt_outlined),
                          label: Text('add_product_camera'.tr()),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    key: _nameFieldKey,
                    child: ProductAutocompleteField(
                      controller: _nameController,
                      search: _searchNameSuggestions,
                      onInteraction: () => _ensureAutocompleteVisible(_nameFieldKey),
                      onSelected: (CatalogItem item) {
                        _categoryController.text = item.category;
                        _applyCategoryPresetIfExists(item.category);
                        _barcodeController.text = item.barcode ?? '';
                        if ((item.defaultImagePath ?? '').isNotEmpty) {
                          setState(() {
                            _localImagePath = item.defaultImagePath;
                          });
                        }
                        _ensureAutocompleteVisible(_nameFieldKey);
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    key: _categoryFieldKey,
                    child: _CategoryAutocompleteField(
                      controller: _categoryController,
                      categories: _categoryPresets,
                      onSelected: _applyCategoryPreset,
                      onInteraction: () =>
                          _ensureAutocompleteVisible(_categoryFieldKey),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _barcodeController,
                    decoration: InputDecoration(
                      labelText: 'add_product_barcode_label'.tr(),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: FilledButton.tonal(
                      onPressed: _isLoadingLookup ? null : _lookupFromBarcode,
                      child: Text(
                        _isLoadingLookup
                            ? 'add_product_searching'.tr()
                            : 'add_product_search_db'.tr(),
                        textScaler: TextScaler.linear(textScale),
                      ),
                    ),
                  ),
                  if (!widget.catalogOnlyAdd &&
                      !_isCatalogOnlyEdit) ...<Widget>[
                    const SizedBox(height: 12),
                    Text(
                      'add_product_batches_header'.tr(),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                      textScaler: TextScaler.linear(textScale),
                    ),
                    const SizedBox(height: 8),
                    ..._batches.asMap().entries.map((
                      MapEntry<int, _DraftBatch> entry,
                    ) {
                      final int index = entry.key;
                      final _DraftBatch batch = entry.value;
                      final DateFormat dateFmt = DateFormat.yMd(
                        context.locale.toString(),
                      );
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: Theme.of(
                              context,
                            ).colorScheme.outlineVariant.withValues(alpha: 0.5),
                          ),
                          boxShadow: <BoxShadow>[
                            BoxShadow(
                              color: Theme.of(
                                context,
                              ).colorScheme.shadow.withValues(alpha: 0.06),
                              blurRadius: 12,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: <Widget>[
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .secondaryContainer,
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      'add_product_batch_label'.tr(
                                        namedArgs: <String, String>{
                                          'n': '${index + 1}',
                                        },
                                      ),
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSecondaryContainer,
                                      ),
                                      textScaler: TextScaler.linear(textScale),
                                    ),
                                  ),
                                  Wrap(
                                    spacing: 4,
                                    children: <Widget>[
                                      IconButton(
                                        tooltip:
                                            'add_product_duplicate_batch_tooltip'
                                                .tr(),
                                        onPressed: () => _duplicateBatch(index),
                                        icon: const Icon(Icons.copy_outlined),
                                      ),
                                      IconButton(
                                        tooltip:
                                            'add_product_remove_batch_tooltip'
                                                .tr(),
                                        onPressed: () => _removeBatch(index),
                                        icon: const Icon(Icons.delete_outline),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: <Widget>[
                                  Text(
                                    'add_product_quantity'.tr(),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const Spacer(),
                                  Container(
                                    decoration: BoxDecoration(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .surfaceContainerHighest,
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Row(
                                      children: <Widget>[
                                        IconButton(
                                          onPressed: () =>
                                              _changeQuantity(index, -1),
                                          icon: const Icon(
                                            Icons.remove_circle_outline,
                                          ),
                                        ),
                                        Text(
                                          '${batch.quantity}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        IconButton(
                                          onPressed: () =>
                                              _changeQuantity(index, 1),
                                          icon: const Icon(
                                            Icons.add_circle_outline,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: <Widget>[
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: () => _pickDate(
                                        index: index,
                                        isExpiry: false,
                                      ),
                                      child: Text(
                                        'add_product_buy_date'.tr(
                                          namedArgs: <String, String>{
                                            'date': dateFmt.format(
                                              batch.buyDate.toLocal(),
                                            ),
                                          },
                                        ),
                                        textScaler: TextScaler.linear(
                                          textScale,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: () => _pickDate(
                                        index: index,
                                        isExpiry: true,
                                      ),
                                      child: Text(
                                        'add_product_expiry_date'.tr(
                                          namedArgs: <String, String>{
                                            'date': dateFmt.format(
                                              batch.expiryDate.toLocal(),
                                            ),
                                          },
                                        ),
                                        textScaler: TextScaler.linear(
                                          textScale,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerLowest,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: <Widget>[
                                    const Icon(
                                      Icons.notifications_outlined,
                                      size: 16,
                                    ),
                                    const SizedBox(width: 4),
                                    IconButton(
                                      iconSize: 18,
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      onPressed: () =>
                                          _changeNotifDays(index, -1),
                                      icon: const Icon(
                                        Icons.remove_circle_outline,
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                      ),
                                      child: Text(
                                        'add_product_notif_days'.tr(
                                          namedArgs: <String, String>{
                                            'days': '${batch.notifDaysBefore}',
                                          },
                                        ),
                                        textScaler: TextScaler.linear(textScale),
                                      ),
                                    ),
                                    IconButton(
                                      iconSize: 18,
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      onPressed: () =>
                                          _changeNotifDays(index, 1),
                                      icon: const Icon(Icons.add_circle_outline),
                                    ),
                                    const Spacer(),
                                    TextButton(
                                      onPressed: () => _pickNotifTime(index),
                                      child: Text(
                                        'add_product_notif_at'.tr(
                                          namedArgs: <String, String>{
                                            'time': batch.notifTime,
                                          },
                                        ),
                                        textScaler: TextScaler.linear(textScale),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _addBatchWithDefaults,
                        icon: const Icon(Icons.add),
                        label: Text(
                          'add_product_add_batch'.tr(),
                          textScaler: TextScaler.linear(textScale),
                        ),
                      ),
                    ),
                    if (_editingProduct != null) ...<Widget>[
                      const SizedBox(height: 12),
                      Text(
                        'consumption_history_header'.tr(),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                        textScaler: TextScaler.linear(textScale),
                      ),
                      const SizedBox(height: 8),
                      if (_consumptionHistory.isEmpty)
                        Text(
                          'consumption_history_empty'.tr(),
                          textScaler: TextScaler.linear(textScale),
                        )
                      else
                        ..._consumptionHistory.map((ConsumptionEvent event) {
                          final DateFormat timeFmt = DateFormat.yMd(
                            context.locale.toString(),
                          ).add_Hm();
                          final String eventTime = timeFmt.format(
                            event.createdAt.toLocal(),
                          );
                          final String actionLabel = event.action == 'trash'
                              ? 'consumption_action_trash'.tr()
                              : 'consumption_action_eaten'.tr();
                          final String expiryDate = event.batchExpiryDate == null
                              ? '-'
                              : DateFormat.yMd(
                                  context.locale.toString(),
                                ).format(event.batchExpiryDate!.toLocal());

                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              dense: true,
                              title: Text(
                                'consumption_history_item'.tr(
                                  namedArgs: <String, String>{
                                    'action': actionLabel,
                                    'qty': '${event.quantity}',
                                    'expiry': expiryDate,
                                  },
                                ),
                              ),
                              subtitle: Text(eventTime),
                            ),
                          );
                        }),
                    ],
                    const SizedBox(height: 24),
                  ],
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, keyboardInset + 16),
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    if (_isCatalogOnlyEdit && _editingCatalogItem != null)
                      FloatingActionButton.extended(
                        heroTag: 'catalog-delete-fab',
                        onPressed: _confirmAndDeleteCatalogItem,
                        backgroundColor: Theme.of(
                          context,
                        ).colorScheme.errorContainer,
                        foregroundColor: Theme.of(
                          context,
                        ).colorScheme.onErrorContainer,
                        icon: const Icon(Icons.delete_outline),
                        label: Text('delete'.tr()),
                      )
                    else
                      const SizedBox.shrink(),
                    const Spacer(),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: <Widget>[
                        FloatingActionButton.small(
                          heroTag: 'barcode-scan-fab',
                          onPressed: _isSaving ? null : _scanBarcode,
                          tooltip: 'add_product_scan'.tr(),
                          child: const Icon(Icons.qr_code_scanner),
                        ),
                        const SizedBox(height: 12),
                        FloatingActionButton.extended(
                          heroTag: 'save-item-fab',
                          onPressed: _isSaving ? null : _save,
                          icon: _isSaving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.save_outlined),
                          label: Text(
                            _isSaving
                                ? 'add_product_saving'.tr()
                                : 'add_product_save'.tr(),
                            textScaler: TextScaler.linear(textScale),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DraftBatch {
  const _DraftBatch({
    required this.quantity,
    required this.buyDate,
    required this.expiryDate,
    this.notifDaysBefore = 3,
    this.notifTime = '09:00',
  });

  final int quantity;
  final DateTime buyDate;
  final DateTime expiryDate;
  final int notifDaysBefore;
  final String notifTime;

  _DraftBatch copyWith({
    int? quantity,
    DateTime? buyDate,
    DateTime? expiryDate,
    int? notifDaysBefore,
    String? notifTime,
  }) {
    return _DraftBatch(
      quantity: quantity ?? this.quantity,
      buyDate: buyDate ?? this.buyDate,
      expiryDate: expiryDate ?? this.expiryDate,
      notifDaysBefore: notifDaysBefore ?? this.notifDaysBefore,
      notifTime: notifTime ?? this.notifTime,
    );
  }
}

class _CategoryAutocompleteField extends StatefulWidget {
  const _CategoryAutocompleteField({
    required this.controller,
    required this.categories,
    required this.onSelected,
    this.onInteraction,
  });

  final TextEditingController controller;
  final List<CategoryPreset> categories;
  final ValueChanged<CategoryPreset> onSelected;
  final VoidCallback? onInteraction;

  @override
  State<_CategoryAutocompleteField> createState() =>
      _CategoryAutocompleteFieldState();
}

class _CategoryAutocompleteFieldState
    extends State<_CategoryAutocompleteField> {
  final FocusNode _focusNode = FocusNode();
  List<CategoryPreset> _suggestions = <CategoryPreset>[];

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_updateSuggestions);
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(covariant _CategoryAutocompleteField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.categories != widget.categories) {
      _updateSuggestions();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_updateSuggestions);
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (_focusNode.hasFocus) {
      widget.onInteraction?.call();
      _updateSuggestions();
      return;
    }

    Future<void>.delayed(const Duration(milliseconds: 120), () {
      if (!mounted) {
        return;
      }
      setState(() {
        _suggestions = <CategoryPreset>[];
      });
    });
  }

  void _updateSuggestions() {
    if (!_focusNode.hasFocus) {
      return;
    }

    final String query = widget.controller.text.trim().toLowerCase();
    if (query.isEmpty) {
      if (!mounted) {
        return;
      }
      setState(() {
        _suggestions = <CategoryPreset>[];
      });
      return;
    }

    final bool hadSuggestions = _suggestions.isNotEmpty;
    final Iterable<CategoryPreset> filtered = widget.categories.where(
      (CategoryPreset preset) => preset.name.toLowerCase().contains(query),
    );

    if (!mounted) {
      return;
    }

    final List<CategoryPreset> next = filtered.take(8).toList(growable: false);
    final bool hasExactMatch = next.any(
      (CategoryPreset preset) => preset.name.trim().toLowerCase() == query,
    );

    setState(() {
      _suggestions = hasExactMatch ? <CategoryPreset>[] : next;
    });
    if (!hadSuggestions && _suggestions.isNotEmpty) {
      widget.onInteraction?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        TextField(
          controller: widget.controller,
          focusNode: _focusNode,
          decoration: InputDecoration(
            labelText: 'add_product_category_label'.tr(),
            border: const OutlineInputBorder(),
            suffixIcon: const Icon(Icons.arrow_drop_down),
          ),
        ),
        if (_suggestions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            constraints: const BoxConstraints(maxHeight: 220),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _suggestions.length,
              itemBuilder: (BuildContext context, int index) {
                final CategoryPreset preset = _suggestions[index];
                return ListTile(
                  dense: true,
                  title: Text(preset.name),
                  subtitle: Text(
                    'category_default_days_value'.tr(
                      namedArgs: <String, String>{
                        'days': '${preset.defaultExpiryDays}',
                      },
                    ),
                  ),
                  onTap: () {
                    widget.controller.text = preset.name;
                    widget.controller.selection = TextSelection.fromPosition(
                      TextPosition(offset: widget.controller.text.length),
                    );
                    setState(() {
                      _suggestions = <CategoryPreset>[];
                    });
                    widget.onSelected(preset);
                    widget.onInteraction?.call();
                  },
                );
              },
            ),
          ),
      ],
    );
  }
}
