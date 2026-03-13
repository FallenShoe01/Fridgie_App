import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:fridgie_app/core/db/app_database.dart';

typedef ProductSearch = Future<List<CatalogItem>> Function(String query);
typedef ProductSelected = void Function(CatalogItem item);

class ProductAutocompleteField extends StatefulWidget {
  const ProductAutocompleteField({
    super.key,
    required this.controller,
    required this.search,
    required this.onSelected,
    this.onInteraction,
  });

  final TextEditingController controller;
  final ProductSearch search;
  final ProductSelected onSelected;
  final VoidCallback? onInteraction;

  @override
  State<ProductAutocompleteField> createState() => _ProductAutocompleteFieldState();
}

class _ProductAutocompleteFieldState extends State<ProductAutocompleteField> {
  final FocusNode _focusNode = FocusNode();
  Timer? _debounce;
  List<CatalogItem> _suggestions = <CatalogItem>[];
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
            _suggestions = <CatalogItem>[];
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
          _suggestions = <CatalogItem>[];
        });
        return;
      }

      final bool hadSuggestions = _suggestions.isNotEmpty;
      final List<CatalogItem> results = await widget.search(query);
      if (!mounted) {
        return;
      }
      final String normalizedQuery = query.toLowerCase();
      final List<CatalogItem> others = results.where(
        (CatalogItem item) => item.canonicalName.trim().toLowerCase() != normalizedQuery,
      ).toList(growable: false);

      final bool hasExactMatch = results.length != others.length;

      final List<CatalogItem> visible;
      if (others.isNotEmpty) {
        // Show other suggestions even if an exact match exists (e.g. "bread" matched "bread" and "bread rye").
        visible = others;
      } else if (hasExactMatch) {
        // Only an exact match found — suppress suggestions.
        visible = <CatalogItem>[];
      } else {
        // No exact match and no other-filtered: show all results.
        visible = results;
      }

      setState(() {
        _suggestions = visible;
      });
      if (!hadSuggestions && visible.isNotEmpty) {
        widget.onInteraction?.call();
      }
    });
  }

  void _onFocusChanged() {
    if (_focusNode.hasFocus) {
      widget.onInteraction?.call();
      return;
    }

    if (!_focusNode.hasFocus) {
      Future<void>.delayed(const Duration(milliseconds: 120), () {
        if (!mounted) {
          return;
        }
        setState(() {
          _suggestions = <CatalogItem>[];
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
            suffixIcon: const Icon(Icons.arrow_drop_down),
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
                final CatalogItem item = _suggestions[index];
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
                      _suggestions = <CatalogItem>[];
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
