import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../commission/application/providers/commission_providers.dart';
import '../../domain/models/category.dart';

class CategoryFormDialog extends ConsumerStatefulWidget {
  final Category? existing;
  final Future<String?> Function({
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
  ConsumerState<CategoryFormDialog> createState() => _CategoryFormDialogState();
}

class _CategoryFormDialogState extends ConsumerState<CategoryFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _slug;
  late final TextEditingController _imageUrl;
  late final TextEditingController _sortOrder;
  late bool _isActive;
  bool _saving = false;
  bool _slugEdited = false;

  // Commission override
  bool _overrideCommission = false;
  String _commissionType = 'percentage';
  final _commissionValue = TextEditingController(text: '10');

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
    if (e != null) _loadCommission(e.id);
  }

  @override
  void dispose() {
    _name.dispose();
    _slug.dispose();
    _imageUrl.dispose();
    _sortOrder.dispose();
    _commissionValue.dispose();
    super.dispose();
  }

  Future<void> _loadCommission(String categoryId) async {
    final rule = await ref
        .read(commissionRepositoryProvider)
        .fetchForCategory(categoryId);
    if (!mounted || rule == null) return;
    setState(() {
      _overrideCommission = true;
      _commissionType = rule.commissionType;
      final v = rule.commissionValue;
      _commissionValue.text = v == v.truncateToDouble()
          ? v.toInt().toString()
          : v.toString();
    });
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
    if (_overrideCommission) {
      final cv = double.tryParse(_commissionValue.text.trim());
      if (cv == null || cv < 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Enter a valid platform commission value.'),
            backgroundColor: AppColors.error,
          ),
        );
        return;
      }
      if (_commissionType == 'percentage' && cv > 100) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Platform Commission percentage cannot exceed 100.'),
            backgroundColor: AppColors.error,
          ),
        );
        return;
      }
    }

    setState(() => _saving = true);
    try {
      final categoryId = await widget.onSave(
        name: _name.text.trim(),
        slug: _slug.text.trim(),
        imageUrl:
            _imageUrl.text.trim().isEmpty ? null : _imageUrl.text.trim(),
        sortOrder: int.tryParse(_sortOrder.text.trim()) ?? 0,
        isActive: _isActive,
      );

      if (categoryId != null) {
        final repo = ref.read(commissionRepositoryProvider);
        if (_overrideCommission) {
          final cv = double.parse(_commissionValue.text.trim());
          await repo.upsertRule(
            ruleType: 'category',
            targetId: categoryId,
            commissionType: _commissionType,
            commissionValue: cv,
            isEnabled: true,
          );
          ref.invalidate(categoryCommissionProvider(categoryId));
        } else if (widget.existing != null) {
          await repo.deleteForTarget(categoryId);
          ref.invalidate(categoryCommissionProvider(categoryId));
        }
      }

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
                            const Text(
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
                      const SizedBox(height: 20),

                      // Commission Override
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.percent_rounded,
                                    size: 16, color: AppColors.textSecondary),
                                const SizedBox(width: 8),
                                const Expanded(
                                  child: Text(
                                    'Override Platform Commission',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                ),
                                Switch(
                                  value: _overrideCommission,
                                  onChanged: (v) =>
                                      setState(() => _overrideCommission = v),
                                  activeThumbColor: AppColors.accent,
                                ),
                              ],
                            ),
                            if (!_overrideCommission)
                              const Padding(
                                padding: EdgeInsets.only(top: 4),
                                child: Text(
                                  'Uses global platform commission setting by default.',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ),
                            if (_overrideCommission) ...[
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  Expanded(
                                    child: _CommissionTypeBtn(
                                      label: '% Percentage',
                                      selected: _commissionType == 'percentage',
                                      onTap: () => setState(
                                          () => _commissionType = 'percentage'),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _CommissionTypeBtn(
                                      label: '₹ Fixed',
                                      selected: _commissionType == 'fixed',
                                      onTap: () => setState(
                                          () => _commissionType = 'fixed'),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _commissionValue,
                                decoration: InputDecoration(
                                  labelText: 'Platform Commission Value',
                                  suffixText: _commissionType == 'percentage'
                                      ? '%'
                                      : '₹',
                                  isDense: true,
                                ),
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                      RegExp(r'^\d*\.?\d{0,4}')),
                                ],
                              ),
                            ],
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
              decoration: const BoxDecoration(
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

class _CommissionTypeBtn extends StatelessWidget {
  const _CommissionTypeBtn({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.accent.withValues(alpha: 0.12)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? AppColors.accent : AppColors.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
              color: selected ? AppColors.accent : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
