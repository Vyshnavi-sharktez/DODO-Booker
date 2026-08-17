import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../domain/models/catalog_node.dart';

/// Single form dialog for creating and editing any catalog node at any depth.
/// The parent context is shown at the top when creating a child node.
///
/// When [hasChildren] is true all booking-specific configuration (Bookable
/// toggle, Base Price, Duration) is hidden — the node acts as a navigation
/// node regardless of the stored is_bookable flag. Stored values are never
/// cleared; they reappear automatically once all children are removed.
class CatalogNodeFormDialog extends StatefulWidget {
  const CatalogNodeFormDialog({
    super.key,
    this.existing,
    this.parentNode,
    this.hasChildren = false,
    required this.onSave,
  });

  /// Non-null when editing an existing node.
  final CatalogNode? existing;

  /// Non-null when creating a child — shown as context at the top.
  final CatalogNode? parentNode;

  /// True when the node currently has one or more children. When true,
  /// all booking UI is hidden (values are preserved in the database).
  final bool hasChildren;

  final Future<void> Function({
    required String name,
    required String slug,
    String? description,
    String? imageUrl,
    String? iconKey,
    required int sortOrder,
    required bool isActive,
    required bool isBookable,
    double? basePrice,
    int? estimatedDuration,
    double? minimumOrderAmount,
  }) onSave;

  @override
  State<CatalogNodeFormDialog> createState() => _CatalogNodeFormDialogState();
}

class _CatalogNodeFormDialogState extends State<CatalogNodeFormDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _imageUrl;
  late final TextEditingController _iconKey;
  late final TextEditingController _sortOrder;
  late final TextEditingController _basePrice;
  late final TextEditingController _minOrderAmount;

  late bool _isActive;
  late bool _isBookable;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _description = TextEditingController(text: e?.description ?? '');
    _imageUrl = TextEditingController(text: e?.imageUrl ?? '');
    _iconKey = TextEditingController(text: e?.iconKey ?? '');
    _sortOrder = TextEditingController(text: (e?.sortOrder ?? 0).toString());
    _basePrice = TextEditingController(
      text: e?.basePrice != null ? e!.basePrice!.toStringAsFixed(2) : '',
    );
    _minOrderAmount = TextEditingController(
      text: e?.minimumOrderAmount != null
          ? e!.minimumOrderAmount!.toStringAsFixed(2)
          : '',
    );
    _isActive = e?.isActive ?? true;
    _isBookable = e?.isBookable ?? false;
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _imageUrl.dispose();
    _iconKey.dispose();
    _sortOrder.dispose();
    _basePrice.dispose();
    _minOrderAmount.dispose();
    super.dispose();
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
        slug: _toSlug(_name.text.trim()),
        description:
            _description.text.trim().isEmpty ? null : _description.text.trim(),
        imageUrl:
            _imageUrl.text.trim().isEmpty ? null : _imageUrl.text.trim(),
        iconKey: _iconKey.text.trim().isEmpty ? null : _iconKey.text.trim(),
        sortOrder: int.tryParse(_sortOrder.text.trim()) ?? 0,
        isActive: _isActive,
        isBookable: _isBookable,
        basePrice: _isBookable && _basePrice.text.trim().isNotEmpty
            ? double.tryParse(_basePrice.text.trim())
            : null,
        estimatedDuration: widget.existing?.estimatedDuration,
        minimumOrderAmount:
            _isBookable && _minOrderAmount.text.trim().isNotEmpty
                ? double.tryParse(_minOrderAmount.text.trim())
                : null,
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
        constraints: const BoxConstraints(maxWidth: 580),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(isEdit),
            Flexible(child: _buildForm()),
            _buildFooter(isEdit),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(bool isEdit) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 16, 20),
      decoration: const BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Row(
        children: [
          Icon(
            isEdit ? Icons.edit_rounded : Icons.add_circle_outline_rounded,
            color: Colors.white,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isEdit ? 'Edit Node' : 'New Node',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (!isEdit && widget.parentNode != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Under: ${widget.parentNode!.name}',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded, color: Colors.white70),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _buildForm() {
    return SingleChildScrollView(
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
                labelText: 'Name *',
                hintText: 'e.g. MacBook Air',
              ),
              textCapitalization: TextCapitalization.words,
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 16),

            // Sort Order
            SizedBox(
              width: 140,
              child: TextFormField(
                controller: _sortOrder,
                decoration:
                    const InputDecoration(labelText: 'Sort Order'),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
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

            // ── Toggles ──────────────────────────────────────────────────────
            _buildToggleRow(
              icon: Icons.visibility_outlined,
              label: 'Globally Active',
              subtitle: 'Disable to hide from all catalog paths and search',
              value: _isActive,
              onChanged: (v) => setState(() => _isActive = v),
              activeColor: AppColors.success,
            ),

            // ── Booking configuration ─────────────────────────────────────
            // Hidden when the node has children. A node with children is a
            // navigation node at every depth — booking is only possible at
            // childless leaf nodes. Stored values (is_bookable, base_price,
            // estimated_duration) are never cleared; they reappear here
            // automatically once all children are removed.
            if (widget.hasChildren) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.18),
                  ),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.account_tree_outlined,
                        size: 16, color: AppColors.primary),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Booking configuration is hidden because this node '
                        'has children. It acts as a navigation node. '
                        'Remove all children to configure booking details.',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.primary,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              const SizedBox(height: 10),
              _buildToggleRow(
                icon: Icons.bookmark_outline_rounded,
                label: 'Bookable',
                subtitle: 'Customer can book this node directly',
                value: _isBookable,
                onChanged: (v) => setState(() => _isBookable = v),
                activeColor: AppColors.accent,
              ),

              // ── Service fields (only when bookable) ─────────────────────
              if (_isBookable) ...[
                const SizedBox(height: 20),
                const Divider(),
                const SizedBox(height: 12),
                const Text(
                  'Booking Details',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Only used when this node is booked directly.',
                  style: TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _description,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    hintText: 'Describe this service for customers…',
                    alignLabelWithHint: true,
                  ),
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _basePrice,
                  decoration: const InputDecoration(
                    labelText: 'Base Price (₹)',
                    prefixIcon: Icon(Icons.currency_rupee),
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                        RegExp(r'^\d+\.?\d{0,2}')),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _minOrderAmount,
                  decoration: const InputDecoration(
                    labelText: 'Min Order Amount (₹)',
                    hintText: 'Leave blank for no minimum',
                    prefixIcon: Icon(Icons.production_quantity_limits_rounded),
                    helperText:
                        'Customer must meet this amount to proceed with booking.',
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                        RegExp(r'^\d+\.?\d{0,2}')),
                  ],
                ),

                // AMC plans are managed from the catalog tile (AMC Plans button).
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildToggleRow({
    required IconData icon,
    required String label,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    required Color activeColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: value
            ? activeColor.withValues(alpha: 0.06)
            : AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: value ? activeColor.withValues(alpha: 0.3) : AppColors.border,
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: value ? activeColor : AppColors.textSecondary,
            size: 18,
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: value ? activeColor : AppColors.textPrimary,
                ),
              ),
              Text(
                subtitle,
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textSecondary),
              ),
            ],
          ),
          const Spacer(),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: activeColor,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(bool isEdit) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          OutlinedButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            style: OutlinedButton.styleFrom(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 12),
          FilledButton(
            onPressed: _saving ? null : _submit,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding:
                  const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
            ),
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : Text(isEdit ? 'Save Changes' : 'Create Node'),
          ),
        ],
      ),
    );
  }
}

