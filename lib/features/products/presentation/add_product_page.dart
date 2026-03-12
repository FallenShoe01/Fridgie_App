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

class AddProductPage extends ConsumerStatefulWidget {
  const AddProductPage({super.key});

  @override
  ConsumerState<AddProductPage> createState() => _AddProductPageState();
}

class _AddProductPageState extends ConsumerState<AddProductPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

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
  String? _localImagePath;
  List<CategoryPreset> _categoryPresets = <CategoryPreset>[];

  @override
  void initState() {
    super.initState();
    _loadCategoryPresets();
  }

  @override
  void dispose() {
    _barcodeController.dispose();
    _nameController.dispose();
    _categoryController.dispose();
    super.dispose();
  }

  Future<void> _loadCategoryPresets() async {
    final List<CategoryPreset> presets =
        await ref.read(categoryPresetStoreProvider).getAll();
    if (!mounted) {
      return;
    }
    setState(() {
      _categoryPresets = presets;
    });
  }

  void _applyCategoryPreset(CategoryPreset preset) {
    _categoryController.text = preset.name;
    setState(() {
      _batches.setAll(
        0,
        _batches.map(
          (_DraftBatch batch) => batch.copyWith(
            expiryDate: batch.buyDate.add(
              Duration(days: preset.defaultExpiryDays),
            ),
          ),
        ),
      );
    });
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

    final LookupResult? result = await lookupService.lookupByBarcode(barcode);

    if (!mounted) {
      return;
    }

    if (result != null) {
      _nameController.text = result.name;
      _categoryController.text = (result.category ?? '').trim();

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

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('add_product_found'.tr())),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('add_product_not_found'.tr())),
      );
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

  Future<void> _pickDate({
    required int index,
    required bool isExpiry,
  }) async {
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
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    final AppDatabase db = ref.read(dbProvider);
    final productRepository = ref.read(productRepositoryProvider);
    final batchRepository = ref.read(batchRepositoryProvider);
    final notificationService = ref.read(notificationServiceProvider);

    final String barcode = _barcodeController.text.trim();
    final String name = _nameController.text.trim();
    final String category = _categoryController.text.trim().isEmpty
        ? 'unknown'
        : _categoryController.text.trim();
    final int productId = await productRepository.createProduct(
      ProductsCompanion.insert(
        canonicalName: name,
        barcode: barcode.isEmpty ? const drift.Value.absent() : drift.Value(barcode),
        category: drift.Value(category),
        defaultImagePath: _localImagePath == null
            ? const drift.Value.absent()
            : drift.Value(_localImagePath),
        source: drift.Value(barcode.isEmpty ? 'manual' : 'lookup_or_manual'),
      ),
    );

    for (final _DraftBatch batch in _batches) {
      final int batchId = await batchRepository.createBatch(
        ProductBatchesCompanion.insert(
          productId: productId,
          buyDate: drift.Value(batch.buyDate),
          expiryDate: batch.expiryDate,
          quantity: drift.Value(batch.quantity),
        ),
      );

      await notificationService.scheduleExpiryNotification(
        notificationId: batchId,
        title: 'Expiry reminder',
        body: '$name expires soon',
        expiryDate: batch.expiryDate,
        daysBefore: batch.notifDaysBefore,
        hhmm: batch.notifTime,
      );
    }

    if (_localImagePath != null) {
      await db.into(db.productImages).insert(
            ProductImagesCompanion.insert(
              productId: productId,
              barcode: barcode.isEmpty
                  ? const drift.Value.absent()
                  : drift.Value(barcode),
              localPath: _localImagePath!,
            ),
          );
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _isSaving = false;
    });

    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final double textScale = MediaQuery.textScalerOf(context).scale(1).clamp(
          1,
          1.25,
        );
    final double previewSize = MediaQuery.sizeOf(context).width * 0.4;

    return Scaffold(
      appBar: AppBar(
        title: Text('add_product_title'.tr()),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _scanBarcode,
        icon: const Icon(Icons.qr_code_scanner),
        label: Text('add_product_scan'.tr()),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: FilledButton(
          onPressed: _isSaving ? null : _save,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Text(
              _isSaving ? 'add_product_saving'.tr() : 'add_product_save'.tr(),
              textScaler: TextScaler.linear(textScale),
            ),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
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
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.photo_outlined,
                            size: 42,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
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
              const SizedBox(height: 16),
              TextField(
                controller: _barcodeController,
                decoration: InputDecoration(
                  labelText: 'add_product_barcode_label'.tr(),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              FilledButton.tonal(
                onPressed: _isLoadingLookup ? null : _lookupFromBarcode,
                child: Text(
                  _isLoadingLookup
                      ? 'add_product_searching'.tr()
                      : 'add_product_search_db'.tr(),
                  textScaler: TextScaler.linear(textScale),
                ),
              ),
              const SizedBox(height: 16),
              ProductAutocompleteField(
                controller: _nameController,
                search: ref.read(productRepositoryProvider).autocompleteByName,
                onSelected: (Product product) {
                  _categoryController.text = product.category;
                  if ((product.defaultImagePath ?? '').isNotEmpty) {
                    setState(() {
                      _localImagePath = product.defaultImagePath;
                    });
                  }
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _categoryController,
                decoration: InputDecoration(
                  labelText: 'add_product_category_label'.tr(),
                  border: const OutlineInputBorder(),
                ),
              ),
              if (_categoryPresets.isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _categoryPresets
                      .map(
                        (CategoryPreset preset) => ActionChip(
                          onPressed: () => _applyCategoryPreset(preset),
                          label: Text(
                            '${preset.name} (${preset.defaultExpiryDays}d)',
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                'add_product_batches_header'.tr(),
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                textScaler: TextScaler.linear(textScale),
              ),
              const SizedBox(height: 8),
              ..._batches.asMap().entries.map((MapEntry<int, _DraftBatch> entry) {
                final int index = entry.key;
                final _DraftBatch batch = entry.value;
                final DateFormat dateFmt =
                    DateFormat.yMd(context.locale.toString());
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: <Widget>[
                            Text('add_product_batch_label'.tr(
                              namedArgs: <String, String>{'n': '${index + 1}'},
                            ), textScaler: TextScaler.linear(textScale)),
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
                                      'add_product_remove_batch_tooltip'.tr(),
                                  onPressed: () => _removeBatch(index),
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              ],
                            ),
                          ],
                        ),
                        Row(
                          children: <Widget>[
                            Text('add_product_quantity'.tr()),
                            const SizedBox(width: 8),
                            IconButton(
                              onPressed: () => _changeQuantity(index, -1),
                              icon: const Icon(Icons.remove_circle_outline),
                            ),
                            Text('${batch.quantity}'),
                            IconButton(
                              onPressed: () => _changeQuantity(index, 1),
                              icon: const Icon(Icons.add_circle_outline),
                            ),
                          ],
                        ),
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () =>
                                    _pickDate(index: index, isExpiry: false),
                                child: Text(
                                  'add_product_buy_date'.tr(namedArgs: <String,
                                      String>{
                                    'date': dateFmt
                                        .format(batch.buyDate.toLocal()),
                                  }),
                                  textScaler: TextScaler.linear(textScale),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () =>
                                    _pickDate(index: index, isExpiry: true),
                                child: Text(
                                  'add_product_expiry_date'.tr(namedArgs: <String,
                                      String>{
                                    'date': dateFmt
                                        .format(batch.expiryDate.toLocal()),
                                  }),
                                  textScaler: TextScaler.linear(textScale),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: <Widget>[
                            const Icon(Icons.notifications_outlined, size: 16),
                            const SizedBox(width: 4),
                            IconButton(
                              iconSize: 18,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () => _changeNotifDays(index, -1),
                              icon: const Icon(Icons.remove_circle_outline),
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 4),
                              child: Text('add_product_notif_days'.tr(
                                namedArgs: <String, String>{
                                  'days': '${batch.notifDaysBefore}',
                                },
                              ), textScaler: TextScaler.linear(textScale)),
                            ),
                            IconButton(
                              iconSize: 18,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () => _changeNotifDays(index, 1),
                              icon: const Icon(Icons.add_circle_outline),
                            ),
                            const SizedBox(width: 12),
                            TextButton(
                              onPressed: () => _pickNotifTime(index),
                              child: Text('add_product_notif_at'.tr(
                                namedArgs: <String, String>{
                                  'time': batch.notifTime,
                                },
                              ), textScaler: TextScaler.linear(textScale)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () {
                    final _DraftBatch last = _batches.last;
                    setState(() {
                      _batches.add(last.copyWith());
                    });
                  },
                  icon: const Icon(Icons.add),
                  label: Text(
                    'add_product_add_batch'.tr(),
                    textScaler: TextScaler.linear(textScale),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
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
