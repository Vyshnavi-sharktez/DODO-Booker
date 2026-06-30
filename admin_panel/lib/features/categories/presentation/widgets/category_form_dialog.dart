import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/models/category.dart';

class CategoryFormDialog extends StatefulWidget {
  final Category? existing;
  final Future<void> Function({
    required String name,
    required String slug,
    String? imageUrl,
    required int sortOrder,
    required bool isActive,
  }) onSave;

  const CategoryFormDialog({
    super.key,
    this.existing,
    required this.onSave,
  });

  @override
  State<CategoryFormDialog> createState() => _CategoryFormDialogState();
}

class _CategoryFormDialogState extends State<CategoryFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _slug;
  late final TextEditingController _imageUrl;
  late final TextEditingController _sortOrder;
  late bool _isActive;
  bool _saving = false;
  bool _slugEdited = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _slug = TextEditingController(text: e?.slug ?? '');
    _imageUrl = TextEditingController(text: e?.imageUrl ?? '');
    _sortOrder = TextEditingController(text: (e?.sortOrder ?? 0).toString());
    _isActive = e?.isActive ?? true;
    _slugEdited = e != null;
  }

  @override
  void dispose() {
    _name.dispose();
    _slug.dispose();
    _imageUrl.dispose();
    _sortOrder.dispose();
    super.dispose();
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
        name: _name.text.trim(),
        slug: _slug.text.trim(),
        imageUrl:
            _imageUrl.text.trim().isEmpty ? null : _imageUrl.text.trim(),
        sortOrder: int.tryParse(_sortOrder.text.trim()) ?? 0,
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
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header ───────────────────────────────────────────────────────
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
                    isEdit ? 'Edit Category' : 'New Category',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white70),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),

            // ── Form ─────────────────────────────────────────────────────────
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Name
                      TextFormField(
                        controller: _name,
                        decoration: const InputDecoration(
                          labelText: 'Category Name *',
                          hintText: 'e.g. Plumbing',
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
                          hintText: 'e.g. plumbing',
                          helperText: 'Auto-generated from name. Lowercase, hyphens only.',
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

                      // Sort Order
                      SizedBox(
                        width: 120,
                        child: TextFormField(
                          controller: _sortOrder,
                          decoration: const InputDecoration(
                            labelText: 'Sort Order',
                          ),
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Image URL
                      TextFormField(
                        controller: _imageUrl,
                        decoration: const InputDecoration(
                          labelText: 'Image URL',
                          hintText: 'https://...',
                          prefixIcon: Icon(Icons.image_outlined),
                        ),
                        keyboardType: TextInputType.url,
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

            // ── Footer actions ────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: AppColors.border),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: _saving ? null : () => Navigator.of(context).pop(),
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
                        : Text(isEdit ? 'Save Changes' : 'Create Category'),
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
