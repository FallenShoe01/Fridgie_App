import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fridgie_app/app/providers.dart';
import 'package:fridgie_app/core/db/app_database.dart';
import 'package:go_router/go_router.dart';

class EditProductPage extends ConsumerStatefulWidget {
  const EditProductPage({super.key, required this.productId});

  final int productId;

  @override
  ConsumerState<EditProductPage> createState() => _EditProductPageState();
}

class _EditProductPageState extends ConsumerState<EditProductPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _categoryController = TextEditingController();

  Product? _product;
  List<ProductBatch> _batches = <ProductBatch>[];
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _categoryController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final AppDatabase db = ref.read(dbProvider);
    final Product? product = await (db.select(db.products)
          ..where((Products tbl) => tbl.id.equals(widget.productId)))
        .getSingleOrNull();

    final List<ProductBatch> batches = await ref
        .read(batchRepositoryProvider)
        .getBatchesByProduct(widget.productId);

    if (!mounted) return;
    setState(() {
      _product = product;
      _batches = batches;
      if (product != null) {
        _nameController.text = product.canonicalName;
        _categoryController.text = product.category;
      }
      _loading = false;
    });
  }

  Future<void> _save() async {
    if (_product == null || !(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    setState(() => _saving = true);

    await ref.read(productRepositoryProvider).updateProduct(
          _product!.copyWith(
            canonicalName: _nameController.text.trim(),
            category: _categoryController.text.trim(),
            updatedAt: DateTime.now(),
          ),
        );

    if (mounted) {
      setState(() => _saving = false);
      context.pop(true);
    }
  }

  Future<void> _deleteBatch(ProductBatch batch) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        content: Text('add_product_remove_batch_tooltip'.tr()),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('confirm_cancel'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('confirm_ok'.tr()),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(batchRepositoryProvider).deleteBatch(batch.id);
      await _loadData();
    }
  }

  Future<void> _addBatch() async {
    DateTime expiryDate = DateTime.now().add(const Duration(days: 7));
    final TextEditingController qtyCtrl = TextEditingController(text: '1');

    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) {
        return StatefulBuilder(
          builder: (BuildContext ctx2, StateSetter setDlg) {
            return AlertDialog(
              title: Text('add_product_add_batch'.tr()),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('table_header_expiry'.tr()),
                    trailing: Text(
                      DateFormat.yMMMd(context.locale.toString())
                          .format(expiryDate),
                    ),
                    onTap: () async {
                      final DateTime? picked = await showDatePicker(
                        context: ctx2,
                        initialDate: expiryDate,
                        firstDate:
                            DateTime.now().subtract(const Duration(days: 365)),
                        lastDate:
                            DateTime.now().add(const Duration(days: 3650)),
                      );
                      if (picked != null) {
                        setDlg(() => expiryDate = picked);
                      }
                    },
                  ),
                  TextField(
                    controller: qtyCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'add_product_quantity'.tr(),
                    ),
                  ),
                ],
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: Text('confirm_cancel'.tr()),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: Text('confirm_ok'.tr()),
                ),
              ],
            );
          },
        );
      },
    );

    qtyCtrl.dispose();

    if (ok == true && mounted) {
      await ref.read(batchRepositoryProvider).createBatch(
            ProductBatchesCompanion.insert(
              productId: widget.productId,
              expiryDate: expiryDate,
              quantity: drift.Value<int>(
                int.tryParse(qtyCtrl.text.trim()) ?? 1,
              ),
            ),
          );
      await _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text('product_action_edit'.tr())),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_product == null) {
      return Scaffold(
        appBar: AppBar(title: Text('product_action_edit'.tr())),
        body: Center(child: Text('product_not_found'.tr())),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('product_action_edit'.tr()),
        actions: <Widget>[
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text('add_product_save'.tr()),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            if (_product!.defaultImagePath != null &&
                _product!.defaultImagePath!.isNotEmpty &&
                File(_product!.defaultImagePath!).existsSync())
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(
                    File(_product!.defaultImagePath!),
                    height: 160,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            TextFormField(
              controller: _nameController,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'table_header_name'.tr(),
                border: const OutlineInputBorder(),
              ),
              validator: (String? value) {
                if (value == null || value.trim().isEmpty) {
                  return 'table_header_name'.tr();
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _categoryController,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'table_header_category'.tr(),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(
                  'add_product_batches_header'.tr(),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                FilledButton.tonal(
                  onPressed: _addBatch,
                  child: Text('add_product_add_batch'.tr()),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_batches.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'product_no_batches'.tr(),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              )
            else
              ..._batches.map((ProductBatch batch) {
                final String expiryLabel = DateFormat.yMMMd(
                  context.locale.toString(),
                ).format(batch.expiryDate);

                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(
                      'add_product_expiry_date'.tr(
                        namedArgs: <String, String>{'date': expiryLabel},
                      ),
                    ),
                    subtitle: Text(
                      '${' add_product_quantity'.tr()}: ${batch.quantity}',
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'add_product_remove_batch_tooltip'.tr(),
                      onPressed: () => _deleteBatch(batch),
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
