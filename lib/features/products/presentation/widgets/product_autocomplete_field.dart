import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:fridgie_app/core/db/app_database.dart';

typedef ProductSearch = Future<List<Product>> Function(String query);
typedef ProductSelected = void Function(Product product);

class ProductAutocompleteField extends StatefulWidget {
  const ProductAutocompleteField({
    super.key,
    required this.controller,
    required this.search,
    required this.onSelected,
  });

  final TextEditingController controller;
  final ProductSearch search;
  final ProductSelected onSelected;

  @override
  State<ProductAutocompleteField> createState() => _ProductAutocompleteFieldState();
}

class _ProductAutocompleteFieldState extends State<ProductAutocompleteField> {
  final FocusNode _focusNode = FocusNode();
  Timer? _debounce;
  List<Product> _suggestions = <Product>[];
  bool _suppressSuggestionsUntilEdit = false;
  String _selectedText = '';

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.controller.removeListener(_onTextChanged);
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final String currentText = widget.controller.text;
    if (_suppressSuggestionsUntilEdit) {
      if (currentText == _selectedText) {
        if (_suggestions.isNotEmpty && mounted) {
          setState(() {
            _suggestions = <Product>[];
          });
        }
        return;
      }
      _suppressSuggestionsUntilEdit = false;
    }

    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), () async {
      final String query = widget.controller.text.trim();
      if (query.isEmpty) {
        if (!mounted) {
          return;
        }
        setState(() {
          _suggestions = <Product>[];
        });
        return;
      }

      final List<Product> results = await widget.search(query);
      if (!mounted) {
        return;
      }

      setState(() {
        _suggestions = results;
      });
    });
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus) {
      Future<void>.delayed(const Duration(milliseconds: 120), () {
        if (!mounted) {
          return;
        }
        setState(() {
          _suggestions = <Product>[];
        });
      });
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
            labelText: 'add_product_name_label'.tr(),
            border: const OutlineInputBorder(),
          ),
        ),
        if (_suggestions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            constraints: const BoxConstraints(maxHeight: 180),
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _suggestions.length,
              itemBuilder: (BuildContext context, int index) {
                final Product item = _suggestions[index];
                return ListTile(
                  dense: true,
                  title: Text(item.canonicalName),
                  subtitle: item.category.isEmpty ? null : Text(item.category),
                  onTap: () {
                    widget.controller.text = item.canonicalName;
                    widget.controller.selection = TextSelection.fromPosition(
                      TextPosition(offset: widget.controller.text.length),
                    );
                    _selectedText = item.canonicalName;
                    _suppressSuggestionsUntilEdit = true;
                    setState(() {
                      _suggestions = <Product>[];
                    });
                    widget.onSelected(item);
                  },
                );
              },
            ),
          ),
      ],
    );
  }
}
