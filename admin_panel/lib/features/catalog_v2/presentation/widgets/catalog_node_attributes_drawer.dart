import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../../service_attributes/domain/models/service_attribute.dart';
import '../../../service_attributes/presentation/widgets/attribute_form_dialog.dart';
import '../../application/providers/catalog_node_providers.dart';
import '../../domain/models/catalog_node.dart';

/// Right-side drawer for managing service attributes on a [CatalogNode].
/// Uses [catalogNodeAttributesNotifierProvider] (keyed by node_id) so it
/// operates independently from the legacy [serviceAttributesNotifierProvider].
class CatalogNodeAttributesDrawer extends ConsumerStatefulWidget {
  const CatalogNodeAttributesDrawer({super.key, required this.node});
  final CatalogNode node;

  @override
  ConsumerState<CatalogNodeAttributesDrawer> createState() =>
      _CatalogNodeAttributesDrawerState();
}

class _CatalogNodeAttributesDrawerState
    extends ConsumerState<CatalogNodeAttributesDrawer> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref
            .read(catalogNodeAttributesNotifierProvider.notifier)
            .loadForNode(widget.node.id);
      }
    });
  }

  void _openCreate() {
    final notifier =
        ref.read(catalogNodeAttributesNotifierProvider.notifier);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AttributeFormDialog(
        serviceId: widget.node.id,
        serviceName: widget.node.name,
        onSave: ({
          required serviceId,
          required name,
          required price,
          required discountType,
          required discountValue,
        }) async {
          final attrId = await notifier.createAttribute(
            nodeId: serviceId,
            name: name,
            fieldType: 'dropdown',
            isRequired: false,
          );
          await notifier.createOption(
            attributeId: attrId,
            optionName: name,
            priceAdjustment: price,
            discountType: discountType,
            discountValue: discountValue,
          );
        },
      ),
    );
  }

  void _openEdit(ServiceAttribute attr) {
    final notifier =
        ref.read(catalogNodeAttributesNotifierProvider.notifier);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AttributeFormDialog(
        existing: attr,
        serviceId: widget.node.id,
        serviceName: widget.node.name,
        onSave: ({
          required serviceId,
          required name,
          required price,
          required discountType,
          required discountValue,
        }) async {
          await notifier.updateAttribute(
            attr.id,
            name: name,
            fieldType: 'dropdown',
            isRequired: false,
          );
          if (attr.options.isNotEmpty) {
            await notifier.updateOption(
              attr.options.first.id,
              optionName: name,
              priceAdjustment: price,
              discountType: discountType,
              discountValue: discountValue,
            );
          } else {
            await notifier.createOption(
              attributeId: attr.id,
              optionName: name,
              priceAdjustment: price,
              discountType: discountType,
              discountValue: discountValue,
            );
          }
        },
      ),
    );
  }

  Future<void> _delete(ServiceAttribute attr) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Delete Attribute'),
        content: Text('Delete "${attr.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref
        .read(catalogNodeAttributesNotifierProvider.notifier)
        .deleteAttribute(attr.id);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Attribute deleted.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final attrsAsync = ref.watch(catalogNodeAttributesNotifierProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(),
        _buildAddButton(),
        Expanded(
          child: attrsAsync.when(
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (e, _) => const Center(
              child: Text('Error loading attributes.',
                  style: TextStyle(color: AppColors.error)),
            ),
            data: (attrs) {
              if (attrs.isEmpty) {
                return const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.tune_outlined,
                          size: 40, color: AppColors.textSecondary),
                      SizedBox(height: 12),
                      Text('No attributes yet.',
                          style:
                              TextStyle(color: AppColors.textSecondary)),
                    ],
                  ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                itemCount: attrs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) => _AttributeItem(
                  attr: attrs[i],
                  onEdit: _openEdit,
                  onDelete: _delete,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 12, 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Attributes',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.node.name,
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
            tooltip: 'Close',
          ),
        ],
      ),
    );
  }

  Widget _buildAddButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _openCreate,
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Add Entry'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.accent,
            side: const BorderSide(color: AppColors.accent),
            padding: const EdgeInsets.symmetric(vertical: 10),
          ),
        ),
      ),
    );
  }
}

// ── Attribute item ─────────────────────────────────────────────────────────────

class _AttributeItem extends StatelessWidget {
  const _AttributeItem({
    required this.attr,
    required this.onEdit,
    required this.onDelete,
  });

  final ServiceAttribute attr;
  final void Function(ServiceAttribute) onEdit;
  final void Function(ServiceAttribute) onDelete;

  @override
  Widget build(BuildContext context) {
    final price = attr.options.isNotEmpty
        ? attr.options.first.priceAdjustment
        : 0.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  attr.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (price > 0) ...[
                  const SizedBox(height: 2),
                  Text(
                    '₹${price.toStringAsFixed(0)}',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 15),
            tooltip: 'Edit entry',
            color: AppColors.textSecondary,
            onPressed: () => onEdit(attr),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 15),
            tooltip: 'Delete entry',
            color: AppColors.error,
            onPressed: () => onDelete(attr),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ],
      ),
    );
  }
}

