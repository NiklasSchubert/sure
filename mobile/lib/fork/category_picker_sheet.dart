import 'package:flutter/material.dart';

import '../models/category.dart' as models;
import 'category_avatar.dart';
import 'fork_strings.dart';

Future<models.Category?> showCategoryPicker(
  BuildContext context, {
  required List<models.Category> categories,
  String? selectedCategoryId,
}) {
  return showModalBottomSheet<models.Category>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _CategoryPickerSheet(
      categories: categories,
      selectedCategoryId: selectedCategoryId,
    ),
  );
}

class _CategoryPickerSheet extends StatefulWidget {
  final List<models.Category> categories;
  final String? selectedCategoryId;

  const _CategoryPickerSheet({
    required this.categories,
    required this.selectedCategoryId,
  });

  @override
  State<_CategoryPickerSheet> createState() => _CategoryPickerSheetState();
}

class _CategoryPickerSheetState extends State<_CategoryPickerSheet> {
  String _query = '';

  List<models.Category> _orderedCategories() {
    final byName = [...widget.categories]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final parents = byName.where((c) => c.parent == null);

    return [
      for (final parent in parents) ...[
        parent,
        ...byName.where((c) => c.parent?.id == parent.id),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final needle = _query.trim().toLowerCase();
    final visible = _orderedCategories()
        .where((c) => c.displayName.toLowerCase().contains(needle))
        .toList();
    final maxHeight = MediaQuery.of(context).size.height * 0.75;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: ForkStrings.searchCategories,
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: visible.length,
              itemBuilder: (context, index) {
                final category = visible[index];
                final isChild = category.parent != null;
                return ListTile(
                  contentPadding: EdgeInsets.only(
                    left: isChild ? 40 : 16,
                    right: 16,
                  ),
                  leading: CategoryAvatar(category: category, size: 36),
                  title: Text(category.name),
                  trailing: category.id == widget.selectedCategoryId
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () => Navigator.of(context).pop(category),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
