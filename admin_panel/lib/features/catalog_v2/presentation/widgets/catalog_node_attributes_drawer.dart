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
          required fieldType,
          required isRequired,
        }) async {
          await notifier.createAttribute(
            nodeId: serviceId,
            name: name,
            fieldType: fieldType,
            isRequired: isRequired,
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
          required fieldType,
          required isRequired,
        }) async {
          await notifier.updateAttribute(
            attr.id,
            name: name,
            fieldType: fieldType,
            isRequired: isRequired,
          );
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
          label: const Text('Add Attribute'),
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
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Name + tags + edit/delete ──────────────────────────────────
          Row(
            children: [
              Expanded(
                child: Text(
                  attr.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              if (attr.isRequired) ...[
                _Tag('Required', AppColors.error.withValues(alpha: 0.1),
                    AppColors.error),
                const SizedBox(width: 4),
              ],
              _Tag(attr.fieldType,
                  AppColors.primary.withValues(alpha: 0.08), AppColors.primary),
              const SizedBox(width: 2),
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 15),
                tooltip: 'Edit attribute',
                color: AppColors.textSecondary,
                onPressed: () => onEdit(attr),
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 15),
                tooltip: 'Delete attribute',
                color: AppColors.error,
                onPressed: () => onDelete(attr),
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
            ],
          ),

        ],
      ),
    );
  }
}

// ── Label tag ──────────────────────────────────────────────────────────────────

class _Tag extends StatelessWidget {
  const _Tag(this.label, this.bg, this.fg);
  final String label;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
      child: Text(label,
          style: TextStyle(
              fontSize: 11, color: fg, fontWeight: FontWeight.w500)),
    );
  }
}
