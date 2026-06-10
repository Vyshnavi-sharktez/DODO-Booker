import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../categories/domain/models/category.dart';
import '../../../sub_categories/domain/models/sub_category.dart';
import '../../domain/models/service.dart';

class ServiceFormDialog extends StatefulWidget {
  final Service? existing;
  final List<Category> categories;
  final List<SubCategory> allSubCategories;
  final Future<void> Function({
    required String categoryId,
    required String subCategoryId,
    required String name,
    required String slug,
    String? description,
    required double basePrice,
    required int estimatedDuration,
    String? imageUrl,
    required bool isActive,
  }) onSave;

  const ServiceFormDialog({
    super.key,
    this.existing,
    required this.categories,
    required this.allSubCategories,
    required this.onSave,
  });

  @override
  State<ServiceFormDialog> createState() => _ServiceFormDialogState();
}

class _ServiceFormDialogState extends State<ServiceFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _slug;
  late final TextEditingController _description;
  late final TextEditingController _basePrice;
  late final TextEditingController _estimatedDuration;
  late final TextEditingController _imageUrl;
  late bool _isActive;
  String? _selectedCategoryId;
  String? _selectedSubCategoryId;
  bool _saving = false;
  bool _slugEdited = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _slug = TextEditingController(text: e?.slug ?? '');
    _description = TextEditingController(text: e?.description ?? '');
    _basePrice = TextEditingController(
      text: e != null ? e.basePrice.toStringAsFixed(2) : '',
    );
    _estimatedDuration = TextEditingController(
      text: e != null ? e.estimatedDuration.toString() : '',
    );
    _imageUrl = TextEditingController(text: e?.imageUrl ?? '');
    _isActive = e?.isActive ?? true;
    _selectedCategoryId =
        e?.categoryId.isNotEmpty == true ? e!.categoryId : null;
    _selectedSubCategoryId =
        e?.subCategoryId.isNotEmpty == true ? e!.subCategoryId : null;
    _slugEdited = e != null;
  }

  @override
  void dispose() {
    _name.dispose();
    _slug.dispose();
    _description.dispose();
    _basePrice.dispose();
    _estimatedDuration.dispose();
    _imageUrl.dispose();
    super.dispose();
  }

  List<SubCategory> get _filteredSubCategories {
    if (_selectedCategoryId == null) return [];
    return widget.allSubCategories
        .where((s) => s.categoryId == _selectedCategoryId)
        .toList();
  }

  void _onNameChanged(String value) {
    if (!_slugEdited) {
      _slug.text = _toSlug(value);
    }
  }

  String _toSlug(String value) {
    return value
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'[^a-z0-9\s-]'), '')
        .replaceAll(RegExp(r'\s+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await widget.onSave(
        categoryId: _selectedCategoryId!,
        subCategoryId: _selectedSubCategoryId!,
        name: _name.text.trim(),
        slug: _slug.text.trim(),
        description: _description.text.trim().isEmpty
            ? null
            : _description.text.trim(),
        basePrice: double.parse(_basePrice.text.trim()),
        estimatedDuration: int.tryParse(_estimatedDuration.text.trim()) ?? 0,
        imageUrl: _imageUrl.text.trim().isEmpty ? null : _imageUrl.text.trim(),
        isActive: _isActive,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    final subCats = _filteredSubCategories;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header ────────────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 20),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  Icon(
                    isEdit
                        ? Icons.edit_rounded
                        : Icons.add_circle_outline_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    isEdit ? 'Edit Service' : 'New Service',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon:
                        const Icon(Icons.close_rounded, color: Colors.white70),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),

            // ── Form ──────────────────────────────────────────────────────────
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Category dropdown
                      DropdownButtonFormField<String>(
                        // ignore: deprecated_member_use
                        value: _selectedCategoryId,
                        decoration: const InputDecoration(
                          labelText: 'Category *',
                          hintText: 'Select a category',
                        ),
                        items: widget.categories
                            .map(
                              (c) => DropdownMenuItem(
                                value: c.id,
                                child: Text(c.name),
                              ),
                            )
                            .toList(),
                        onChanged: (v) {
                          setState(() {
                            _selectedCategoryId = v;
                            // Reset sub-category when category changes
                            final stillValid = subCats
                                .any((s) => s.id == _selectedSubCategoryId);
                            if (!stillValid) _selectedSubCategoryId = null;
                          });
                        },
                        validator: (v) =>
                            v == null ? 'Please select a category' : null,
                        isExpanded: true,
                      ),
                      const SizedBox(height: 16),

                      // Sub Category dropdown
                      DropdownButtonFormField<String>(
                        // ignore: deprecated_member_use
                        value: _selectedSubCategoryId,
                        decoration: InputDecoration(
                          labelText: 'Sub Category *',
                          hintText: _selectedCategoryId == null
                              ? 'Select a category first'
                              : subCats.isEmpty
                                  ? 'No sub categories for this category'
                                  : 'Select a sub category',
                        ),
                        items: subCats
                            .map(
                              (s) => DropdownMenuItem(
                                value: s.id,
                                child: Text(s.name),
                              ),
                            )
                            .toList(),
                        onChanged: subCats.isEmpty
                            ? null
                            : (v) =>
                                setState(() => _selectedSubCategoryId = v),
                        validator: (v) =>
                            v == null ? 'Please select a sub category' : null,
                        isExpanded: true,
                      ),
                      const SizedBox(height: 16),

                      // Name
                      TextFormField(
                        controller: _name,
                        decoration: const InputDecoration(
                          labelText: 'Service Name *',
                          hintText: 'e.g. Full Home Deep Clean',
                        ),
                        textCapitalization: TextCapitalization.words,
                        onChanged: _onNameChanged,
                        validator: (v) =>
                            v == null || v.trim().isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 16),

                      // Slug
                      TextFormField(
                        controller: _slug,
                        decoration: const InputDecoration(
                          labelText: 'Slug *',
                          hintText: 'e.g. full-home-deep-clean',
                          helperText:
                              'Auto-generated from name. Lowercase, hyphens only.',
                        ),
                        onChanged: (_) => _slugEdited = true,
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Required';
                          if (!RegExp(r'^[a-z0-9-]+$').hasMatch(v.trim())) {
                            return 'Lowercase letters, numbers and hyphens only';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Description
                      TextFormField(
                        controller: _description,
                        decoration: const InputDecoration(
                          labelText: 'Description',
                          hintText: 'Brief description of this service',
                        ),
                        maxLines: 3,
                      ),
                      const SizedBox(height: 16),

                      // Base price + Estimated duration (side by side)
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _basePrice,
                              decoration: const InputDecoration(
                                labelText: 'Base Price *',
                                hintText: '0.00',
                                prefixText: '₹ ',
                              ),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                    RegExp(r'^\d*\.?\d{0,2}')),
                              ],
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) {
                                  return 'Required';
                                }
                                final parsed = double.tryParse(v.trim());
                                if (parsed == null || parsed < 0) {
                                  return 'Enter a valid price';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _estimatedDuration,
                              decoration: const InputDecoration(
                                labelText: 'Duration (minutes) *',
                                hintText: 'e.g. 60',
                                suffixText: 'min',
                              ),
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) {
                                  return 'Required';
                                }
                                final parsed = int.tryParse(v.trim());
                                if (parsed == null || parsed <= 0) {
                                  return 'Enter a valid duration';
                                }
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Image URL
                      TextFormField(
                        controller: _imageUrl,
                        decoration: const InputDecoration(
                          labelText: 'Image URL',
                          hintText: 'https://…',
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Active toggle
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _isActive
                                  ? Icons.check_circle_outline_rounded
                                  : Icons.cancel_outlined,
                              color: _isActive
                                  ? AppColors.success
                                  : AppColors.textSecondary,
                              size: 18,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'Active',
                              style: TextStyle(
                                fontSize: 14,
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const Spacer(),
                            Switch(
                              value: _isActive,
                              onChanged: (v) => setState(() => _isActive = v),
                              activeThumbColor: AppColors.success,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ── Footer ────────────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed:
                        _saving ? null : () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                    ),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: _saving ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 28, vertical: 12),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(isEdit ? 'Save Changes' : 'Create Service'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
