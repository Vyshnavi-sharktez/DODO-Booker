import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../service_attributes/application/providers/service_attributes_providers.dart';
import '../../../service_attributes/domain/models/service_attribute.dart';
import '../../../service_attributes/presentation/widgets/attribute_form_dialog.dart';
import '../../../service_attributes/presentation/widgets/attribute_options_dialog.dart';
import '../../../services/domain/models/service.dart';

/// Right-side drawer content showing and editing attributes for [service].
/// Shown inside a [Dialog] opened by CatalogPage.
class ServiceAttributesDrawer extends ConsumerStatefulWidget {
  const ServiceAttributesDrawer({super.key, required this.service});
  final Service service;

  @override
  ConsumerState<ServiceAttributesDrawer> createState() =>
      _ServiceAttributesDrawerState();
}

class _ServiceAttributesDrawerState
    extends ConsumerState<ServiceAttributesDrawer> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref
            .read(serviceAttributesNotifierProvider.notifier)
            .loadForService(widget.service.id);
      }
    });
  }

  void _openCreate() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AttributeFormDialog(
        serviceId: widget.service.id,
        serviceName: widget.service.name,
        onSave: ({
          required serviceId,
          required name,
          required fieldType,
          required isRequired,
        }) async {
          await ref
              .read(serviceAttributesNotifierProvider.notifier)
              .createAttribute(
                serviceId: serviceId,
                name: name,
                fieldType: fieldType,
                isRequired: isRequired,
              );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Attribute created.')),
            );
          }
        },
      ),
    );
  }

  void _openEdit(ServiceAttribute attr) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AttributeFormDialog(
        existing: attr,
        serviceId: widget.service.id,
        serviceName: widget.service.name,
        onSave: ({
          required serviceId,
          required name,
          required fieldType,
          required isRequired,
        }) async {
          await ref
              .read(serviceAttributesNotifierProvider.notifier)
              .updateAttribute(
                attr.id,
                serviceId: serviceId,
                name: name,
                fieldType: fieldType,
                isRequired: isRequired,
              );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Attribute updated.')),
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
        .read(serviceAttributesNotifierProvider.notifier)
        .deleteAttribute(attr.id);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Attribute deleted.')));
    }
  }

  void _openOptions(ServiceAttribute attr) {
    showDialog(
      context: context,
      builder: (_) => AttributeOptionsDialog(
        attributeId: attr.id,
        attributeName: attr.name,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final attrsAsync = ref.watch(serviceAttributesNotifierProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(),
        _buildAddButton(),
        Expanded(
          child: attrsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, s) => const Center(
              child: Text(
                'Error loading attributes.',
                style: TextStyle(color: AppColors.error),
              ),
            ),
            data: (attrs) {
              final serviceAttrs = attrs
                  .where((a) => a.serviceId == widget.service.id)
                  .toList();
              if (serviceAttrs.isEmpty) {
                return const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.tune_outlined,
                          size: 40, color: AppColors.textSecondary),
                      SizedBox(height: 12),
                      Text('No attributes yet.',
                          style: TextStyle(color: AppColors.textSecondary)),
                    ],
                  ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                itemCount: serviceAttrs.length,
                separatorBuilder: (ctx, idx) => const SizedBox(height: 8),
                itemBuilder: (_, i) => _AttributeItem(
                  attr: serviceAttrs[i],
                  onEdit: _openEdit,
                  onDelete: _delete,
                  onOptions: _openOptions,
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
                  'Service Attributes',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.service.name,
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
    required this.onOptions,
  });

  final ServiceAttribute attr;
  final void Function(ServiceAttribute) onEdit;
  final void Function(ServiceAttribute) onDelete;
  final void Function(ServiceAttribute) onOptions;

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
              if (attr.isRequired)
                Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'Required',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.error,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  attr.fieldType,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              if (attr.hasOptions)
                Text(
                  '${attr.options.length} option${attr.options.length == 1 ? "" : "s"}',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                ),
              const Spacer(),
              if (attr.hasOptions)
                TextButton.icon(
                  onPressed: () => onOptions(attr),
                  icon: const Icon(Icons.list_alt_outlined, size: 14),
                  label:
                      const Text('Options', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.accent,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                  ),
                ),
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 15),
                tooltip: 'Edit',
                color: AppColors.textSecondary,
                onPressed: () => onEdit(attr),
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 15),
                tooltip: 'Delete',
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
