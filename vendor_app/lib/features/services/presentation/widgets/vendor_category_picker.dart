import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/constants/app_colors.dart';
import '../../data/datasources/services_remote_datasource.dart';
import '../../domain/models/vendor_category_model.dart';

// ── Tap-to-open tile shown inside the Create Service dialog ───────────────────

class VendorCategoryPicker extends StatelessWidget {
  const VendorCategoryPicker({
    super.key,
    required this.vendorId,
    required this.datasource,
    this.selected,
    required this.onSelect,
  });

  final String vendorId;
  final ServicesRemoteDatasource datasource;
  final VendorCategoryModel? selected;
  final ValueChanged<VendorCategoryModel?> onSelect;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _openSheet(context),
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.background,
          border: Border.all(
            color: selected != null ? AppColors.primary.withAlpha(160) : AppColors.border,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            if (selected?.iconUrl != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: Image.network(
                  selected!.iconUrl!,
                  width: 24,
                  height: 24,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _CategoryAvatar(name: selected!.name, size: 24),
                ),
              ),
              const SizedBox(width: 8),
            ] else if (selected != null) ...[
              _CategoryAvatar(name: selected!.name, size: 24),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                selected?.name ?? 'Select or create a category (optional)',
                style: TextStyle(
                  fontSize: 13,
                  color: selected != null ? AppColors.textPrimary : AppColors.textHint,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (selected != null)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onSelect(null),
                child: const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Icon(Icons.close, size: 16, color: AppColors.textSecondary),
                ),
              )
            else
              const Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }

  Future<void> _openSheet(BuildContext context) async {
    final result = await showModalBottomSheet<VendorCategoryModel>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CategoryPickerSheet(
        vendorId: vendorId,
        datasource: datasource,
        selected: selected,
      ),
    );
    if (result != null) onSelect(result);
  }
}

// ── Bottom sheet: global category list + create new ──────────────────────────

class _CategoryPickerSheet extends StatefulWidget {
  const _CategoryPickerSheet({
    required this.vendorId,
    required this.datasource,
    this.selected,
  });

  final String vendorId;
  final ServicesRemoteDatasource datasource;
  final VendorCategoryModel? selected;

  @override
  State<_CategoryPickerSheet> createState() => _CategoryPickerSheetState();
}

class _CategoryPickerSheetState extends State<_CategoryPickerSheet> {
  List<VendorCategoryModel> _categories = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      // Returns all global categories (not vendor-scoped).
      final data = await widget.datasource.fetchMyVendorCategories();
      if (mounted) {
        setState(() {
          _categories = data.map(VendorCategoryModel.fromMap).toList();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.88,
      expand: false,
      builder: (ctx, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 4),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Row(
                children: [
                  const Text(
                    'Categories',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.only(bottom: 24),
                      children: [
                        // Create new category
                        _CreateCategoryTile(
                          onTap: () => _showCreateForm(ctx),
                        ),
                        const Divider(height: 1, indent: 16, endIndent: 16),
                        if (_categories.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
                            child: const Text(
                              'No categories yet.\nCreate the first one to organise your services.',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.textSecondary,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          )
                        else
                          ..._categories.map(
                            (cat) => _CategoryRow(
                              category: cat,
                              isSelected: widget.selected?.id == cat.id,
                              onTap: () => Navigator.pop(ctx, cat),
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showCreateForm(BuildContext sheetCtx) async {
    final result = await showDialog<VendorCategoryModel>(
      context: sheetCtx,
      builder: (_) => _CategoryFormDialog(
        vendorId: widget.vendorId,
        datasource: widget.datasource,
        existingCategories: _categories,
      ),
    );
    if (result == null || !mounted) return;
    // Add newly created category to the local list and auto-select it.
    setState(() => _categories.add(result));
    if (mounted) Navigator.pop(sheetCtx, result);
  }
}

// ── "+ Create New Category" tile ──────────────────────────────────────────────

class _CreateCategoryTile extends StatelessWidget {
  const _CreateCategoryTile({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.primary.withAlpha(20),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(Icons.add_rounded, color: AppColors.primary, size: 22),
      ),
      title: Text(
        'Create New Category',
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.primary,
        ),
      ),
    );
  }
}

// ── Category row in the global list ──────────────────────────────────────────

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.category,
    required this.isSelected,
    required this.onTap,
  });

  final VendorCategoryModel category;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      selected: isSelected,
      selectedColor: AppColors.primary,
      selectedTileColor: AppColors.primary.withAlpha(12),
      leading: _CategoryAvatar(name: category.name, iconUrl: category.iconUrl, size: 40),
      title: Text(
        category.name,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
      subtitle: category.serviceCount > 0
          ? Text(
              '${category.serviceCount} service${category.serviceCount == 1 ? '' : 's'} by you',
              style: const TextStyle(fontSize: 11.5),
            )
          : null,
      trailing: isSelected
          ? Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 20)
          : null,
    );
  }
}

// ── Create category dialog ────────────────────────────────────────────────────

class _CategoryFormDialog extends StatefulWidget {
  const _CategoryFormDialog({
    required this.vendorId,
    required this.datasource,
    required this.existingCategories,
  });

  final String vendorId;
  final ServicesRemoteDatasource datasource;
  final List<VendorCategoryModel> existingCategories;

  @override
  State<_CategoryFormDialog> createState() => _CategoryFormDialogState();
}

class _CategoryFormDialogState extends State<_CategoryFormDialog> {
  late final TextEditingController _nameCtrl;
  final _picker = ImagePicker();
  Uint8List? _pickedBytes;
  String? _iconUrl;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickIcon() async {
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 512,
      maxHeight: 512,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (mounted) setState(() => _pickedBytes = bytes);
  }

  static String _normalize(String name) =>
      name.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Category name is required');
      return;
    }

    // Client-side duplicate check (normalized: case + whitespace insensitive).
    final normalized = _normalize(name);
    final hasDuplicate = widget.existingCategories.any(
      (c) => _normalize(c.name) == normalized,
    );

    if (hasDuplicate) {
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('"$name" already exists'),
            content: const Text('Select it from the list instead.'),
            contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        if (mounted) Navigator.of(context).pop();
      }
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      String? iconUrl = _iconUrl;
      if (_pickedBytes != null) {
        iconUrl = await widget.datasource.uploadCategoryIcon(
          vendorId: widget.vendorId,
          bytes: _pickedBytes!,
          mimeType: 'image/jpeg',
        );
      }
      final id = await widget.datasource.createVendorCategory(
        vendorId: widget.vendorId,
        name: name,
        iconUrl: iconUrl,
      );
      if (mounted) {
        Navigator.pop(
          context,
          VendorCategoryModel(id: id, name: name, iconUrl: iconUrl),
        );
      }
    } catch (e) {
      if (!mounted) return;
      final isDuplicate = e.toString().contains('unique') ||
          e.toString().contains('duplicate') ||
          e.toString().contains('23505');
      if (isDuplicate) {
        if (mounted) {
          await showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text('"$name" already exists'),
              content: const Text('Select it from the list instead.'),
              contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
          if (mounted) Navigator.of(context).pop();
        }
      } else {
        setState(() {
          _saving = false;
          _error = 'Failed to save. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final iconWidget = _pickedBytes != null
        ? ClipRRect(
            borderRadius: BorderRadius.circular(13),
            child: Image.memory(_pickedBytes!, width: 72, height: 72, fit: BoxFit.cover),
          )
        : _iconUrl != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(13),
                child: Image.network(
                  _iconUrl!,
                  width: 72,
                  height: 72,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Icon(
                    Icons.add_photo_alternate_outlined,
                    color: AppColors.primary,
                    size: 28,
                  ),
                ),
              )
            : Icon(Icons.add_photo_alternate_outlined, color: AppColors.primary, size: 28);

    return AlertDialog(
      title: const Text('New Category'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Icon picker
          GestureDetector(
            onTap: _pickIcon,
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.primary.withAlpha(15),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: iconWidget,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Tap to set icon (optional)',
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _nameCtrl,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: 'Category Name',
              hintText: 'e.g. Home Cleaning',
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onSubmitted: (_) => _save(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: const TextStyle(fontSize: 12, color: Colors.red),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Create'),
        ),
      ],
    );
  }
}

// ── Shared avatar widget ──────────────────────────────────────────────────────

class _CategoryAvatar extends StatelessWidget {
  const _CategoryAvatar({required this.name, this.iconUrl, required this.size});
  final String name;
  final String? iconUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (iconUrl != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.22),
        child: Image.network(
          iconUrl!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _initial(),
        ),
      );
    }
    return _initial();
  }

  Widget _initial() {
    final hue = name.hashCode.abs() % 360;
    final bg = HSLColor.fromAHSL(1, hue.toDouble(), 0.45, 0.90).toColor();
    final fg = HSLColor.fromAHSL(1, hue.toDouble(), 0.50, 0.35).toColor();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(size * 0.22),
      ),
      alignment: Alignment.center,
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: TextStyle(
          fontSize: size * 0.42,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}
