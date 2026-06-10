import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../application/providers/service_attributes_providers.dart';
import '../../domain/models/service_attribute_option.dart';

class AttributeOptionsDialog extends ConsumerStatefulWidget {
  final String attributeId;
  final String attributeName;

  const AttributeOptionsDialog({
    super.key,
    required this.attributeId,
    required this.attributeName,
  });

  @override
  ConsumerState<AttributeOptionsDialog> createState() =>
      _AttributeOptionsDialogState();
}

class _AttributeOptionsDialogState
    extends ConsumerState<AttributeOptionsDialog> {
  final _optionNameController = TextEditingController();
  final _priceAdjController = TextEditingController();
  final _addFormKey = GlobalKey<FormState>();
  bool _adding = false;
  String? _deletingId;

  // Edit state
  String? _editingId;
  final _editNameController = TextEditingController();
  final _editPriceController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _optionNameController.dispose();
    _priceAdjController.dispose();
    _editNameController.dispose();
    _editPriceController.dispose();
    super.dispose();
  }

  void _startEdit(ServiceAttributeOption option) {
    setState(() {
      _editingId = option.id;
      _editNameController.text = option.optionName;
      _editPriceController.text = option.priceAdjustment == 0
          ? ''
          : option.priceAdjustment.toStringAsFixed(2);
    });
  }

  void _cancelEdit() {
    setState(() {
      _editingId = null;
      _editNameController.clear();
      _editPriceController.clear();
    });
  }

  Future<void> _saveEdit() async {
    if (_editingId == null) return;
    setState(() => _saving = true);
    try {
      await ref.read(serviceAttributesNotifierProvider.notifier).updateOption(
            _editingId!,
            optionName: _editNameController.text.trim(),
            priceAdjustment:
                double.tryParse(_editPriceController.text.trim()) ?? 0.0,
          );
      _cancelEdit();
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

  Future<void> _addOption() async {
    if (!_addFormKey.currentState!.validate()) return;
    setState(() => _adding = true);
    try {
      await ref.read(serviceAttributesNotifierProvider.notifier).createOption(
            attributeId: widget.attributeId,
            optionName: _optionNameController.text.trim(),
            priceAdjustment:
                double.tryParse(_priceAdjController.text.trim()) ?? 0.0,
          );
      _optionNameController.clear();
      _priceAdjController.clear();
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
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _deleteOption(String optionId) async {
    setState(() => _deletingId = optionId);
    try {
      await ref
          .read(serviceAttributesNotifierProvider.notifier)
          .deleteOption(optionId);
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
      if (mounted) setState(() => _deletingId = null);
    }
  }

  String _formatPrice(double price) {
    if (price == 0) return 'No adjustment';
    final sign = price > 0 ? '+' : '';
    return '$sign₹${price.toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    final attribute = ref.watch(singleAttributeProvider(widget.attributeId));
    final options = attribute?.options ?? [];
    final isLoading =
        ref.watch(serviceAttributesNotifierProvider).isLoading;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 540),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header ──────────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 20),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.tune_rounded,
                      color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Manage Options',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          widget.attributeName,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (isLoading)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white54,
                      ),
                    ),
                  const SizedBox(width: 4),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded,
                        color: Colors.white70),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),

            // ── Options list ─────────────────────────────────────────────────
            Expanded(
              child: options.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.list_alt_outlined,
                            size: 40,
                            color: AppColors.textSecondary
                                .withValues(alpha: 0.4),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'No options yet',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Add the first option below.',
                            style: TextStyle(
                              color: AppColors.textSecondary
                                  .withValues(alpha: 0.7),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: options.length,
                      separatorBuilder: (_, i) =>
                          const SizedBox(height: 8),
                      itemBuilder: (ctx, i) {
                        final opt = options[i];
                        final isEditing = _editingId == opt.id;

                        if (isEditing) {
                          return _EditOptionRow(
                            nameController: _editNameController,
                            priceController: _editPriceController,
                            onSave: _saving ? null : _saveEdit,
                            onCancel: _cancelEdit,
                            saving: _saving,
                          );
                        }

                        return _OptionTile(
                          option: opt,
                          priceLabel: _formatPrice(opt.priceAdjustment),
                          deleting: _deletingId == opt.id,
                          onEdit: () => _startEdit(opt),
                          onDelete: () => _deleteOption(opt.id),
                        );
                      },
                    ),
            ),

            const Divider(height: 1),

            // ── Add option form ──────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              color: AppColors.background,
              child: Form(
                key: _addFormKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ADD OPTION',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 4,
                          child: TextFormField(
                            controller: _optionNameController,
                            decoration: const InputDecoration(
                              labelText: 'Option Name *',
                              hintText: 'e.g. 2 Bedrooms',
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                            ),
                            textCapitalization: TextCapitalization.words,
                            validator: (v) =>
                                v == null || v.trim().isEmpty
                                    ? 'Required'
                                    : null,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 3,
                          child: TextFormField(
                            controller: _priceAdjController,
                            decoration: const InputDecoration(
                              labelText: 'Price Adj.',
                              hintText: '0.00',
                              prefixText: '₹ ',
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                            ),
                            keyboardType:
                                const TextInputType.numberWithOptions(
                                    decimal: true, signed: true),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                  RegExp(r'^-?\d*\.?\d{0,2}')),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: FilledButton(
                            onPressed: _adding ? null : _addOption,
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 14),
                            ),
                            child: _adding
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.add_rounded,
                                    size: 18, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // ── Footer ──────────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 24, vertical: 14),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                children: [
                  Text(
                    '${options.length} option${options.length == 1 ? '' : 's'}',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 28, vertical: 12),
                    ),
                    child: const Text('Done'),
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

// ── Option tile ───────────────────────────────────────────────────────────────

class _OptionTile extends StatelessWidget {
  final ServiceAttributeOption option;
  final String priceLabel;
  final bool deleting;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _OptionTile({
    required this.option,
    required this.priceLabel,
    required this.deleting,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              option.optionName,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: option.priceAdjustment == 0
                  ? AppColors.background
                  : option.priceAdjustment > 0
                      ? AppColors.success.withValues(alpha: 0.08)
                      : AppColors.error.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: option.priceAdjustment == 0
                    ? AppColors.border
                    : option.priceAdjustment > 0
                        ? AppColors.success.withValues(alpha: 0.3)
                        : AppColors.error.withValues(alpha: 0.3),
              ),
            ),
            child: Text(
              priceLabel,
              style: TextStyle(
                fontSize: 11,
                color: option.priceAdjustment == 0
                    ? AppColors.textSecondary
                    : option.priceAdjustment > 0
                        ? AppColors.success
                        : AppColors.error,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            onPressed: onEdit,
            icon: Icon(Icons.edit_outlined,
                size: 16, color: AppColors.accent),
            tooltip: 'Edit',
            visualDensity: VisualDensity.compact,
          ),
          deleting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : IconButton(
                  onPressed: onDelete,
                  icon: Icon(Icons.delete_outline_rounded,
                      size: 16, color: AppColors.error),
                  tooltip: 'Delete',
                  visualDensity: VisualDensity.compact,
                ),
        ],
      ),
    );
  }
}

// ── Edit option row ──────────────────────────────────────────────────────────

class _EditOptionRow extends StatelessWidget {
  final TextEditingController nameController;
  final TextEditingController priceController;
  final VoidCallback? onSave;
  final VoidCallback onCancel;
  final bool saving;

  const _EditOptionRow({
    required this.nameController,
    required this.priceController,
    required this.onSave,
    required this.onCancel,
    required this.saving,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 4,
                child: TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Option Name',
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: TextField(
                  controller: priceController,
                  decoration: const InputDecoration(
                    labelText: 'Price Adj.',
                    prefixText: '₹ ',
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true, signed: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                        RegExp(r'^-?\d*\.?\d{0,2}')),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: onCancel,
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: onSave,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 10),
                ),
                child: saving
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
