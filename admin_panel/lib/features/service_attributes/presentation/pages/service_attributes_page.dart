import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/admin_back_button.dart';
import '../../application/providers/service_attributes_providers.dart';
import '../../domain/models/service_attribute.dart';
import '../widgets/attribute_form_dialog.dart';

// ── Field type display config ─────────────────────────────────────────────────

const _typeConfig = <String, (String, Color)>{
  'text': ('Text', Color(0xFF718096)),
  'number': ('Number', Color(0xFF3182CE)),
  'dropdown': ('Dropdown', Color(0xFF805AD5)),
  'radio': ('Radio', Color(0xFFDD6B20)),
  'checkbox': ('Checkbox', Color(0xFF319795)),
};

class ServiceAttributesPage extends ConsumerStatefulWidget {
  /// When non-null, the service dropdown is pre-selected to this service id.
  final String? filterServiceId;

  const ServiceAttributesPage({super.key, this.filterServiceId});

  @override
  ConsumerState<ServiceAttributesPage> createState() =>
      _ServiceAttributesPageState();
}

class _ServiceAttributesPageState
    extends ConsumerState<ServiceAttributesPage> {
  String? _selectedServiceId;

  @override
  void initState() {
    super.initState();
    if (widget.filterServiceId != null) {
      _selectedServiceId = widget.filterServiceId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref
              .read(serviceAttributesNotifierProvider.notifier)
              .loadForService(widget.filterServiceId!);
        }
      });
    }
  }

  void _onServiceChanged(String? serviceId) {
    if (serviceId == null || serviceId == _selectedServiceId) return;
    setState(() => _selectedServiceId = serviceId);
    ref
        .read(serviceAttributesNotifierProvider.notifier)
        .loadForService(serviceId);
  }

  String _serviceNameFor(String serviceId) {
    final all = ref.read(serviceDropdownsProvider).valueOrNull ?? [];
    return all.where((s) => s.id == serviceId).firstOrNull?.name ?? '';
  }

  void _openCreate() {
    final sid = _selectedServiceId;
    if (sid == null) return;
    final notifier = ref.read(serviceAttributesNotifierProvider.notifier);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AttributeFormDialog(
        serviceId: sid,
        serviceName: _serviceNameFor(sid),
        onSave: ({
          required serviceId,
          required name,
          required price,
          required discountType,
          required discountValue,
        }) async {
          final attrId = await notifier.createAttribute(
            serviceId: serviceId,
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
    final notifier = ref.read(serviceAttributesNotifierProvider.notifier);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AttributeFormDialog(
        existing: attr,
        serviceId: attr.serviceId,
        serviceName: _serviceNameFor(attr.serviceId),
        onSave: ({
          required serviceId,
          required name,
          required price,
          required discountType,
          required discountValue,
        }) async {
          await notifier.updateAttribute(
            attr.id,
            serviceId: serviceId,
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

  Future<void> _confirmDelete(ServiceAttribute attr) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Delete Attribute'),
        content: Text(
          'Are you sure you want to delete "${attr.name}"?\n\n'
          'This will also delete all its options.\n'
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref
          .read(serviceAttributesNotifierProvider.notifier)
          .deleteAttribute(attr.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Attribute deleted')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Delete failed: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dropdownsAsync = ref.watch(serviceDropdownsProvider);
    final attributesState = ref.watch(serviceAttributesNotifierProvider);
    final dropdowns = dropdownsAsync.valueOrNull ?? [];

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.filterServiceId != null) ...[
            AdminBackButton(
              label: 'Services',
              onTap: () => context.go('/dashboard/services'),
            ),
            const SizedBox(height: 12),
          ],
          // ── Responsive Header ─────────────────────────────────────────────
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 600;
              return Flex(
                direction: narrow ? Axis.vertical : Axis.horizontal,
                crossAxisAlignment: narrow
                    ? CrossAxisAlignment.start
                    : CrossAxisAlignment.center,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Service Attributes',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Define configurable attributes for each service',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  if (narrow) const SizedBox(height: 12) else const Spacer(),
                  FilledButton.icon(
                    onPressed: _selectedServiceId != null ? _openCreate : null,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('New Attribute'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 20),

          // ── Service selector ──────────────────────────────────────────────
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Service:',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(
                    minWidth: 200, maxWidth: 360),
                child: dropdownsAsync.isLoading
                    ? const LinearProgressIndicator()
                    : DropdownButtonFormField<String>(
                        // ignore: deprecated_member_use
                        value: _selectedServiceId,
                        decoration: const InputDecoration(
                          hintText: 'Select a service…',
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                        ),
                        items: dropdowns
                            .map(
                              (s) => DropdownMenuItem(
                                value: s.id,
                                child: Text(
                                  s.name,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: _onServiceChanged,
                        isExpanded: true,
                      ),
              ),
              if (_selectedServiceId != null)
                IconButton(
                  onPressed: () => ref
                      .read(serviceAttributesNotifierProvider.notifier)
                      .refresh(),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  tooltip: 'Refresh',
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          const SizedBox(height: 20),

          // ── Body ──────────────────────────────────────────────────────────
          Expanded(
            child: _selectedServiceId == null
                ? const _NoServiceSelected()
                : attributesState.when(
                    loading: () => const Center(
                        child: CircularProgressIndicator()),
                    error: (e, _) => Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.error_outline_rounded,
                              size: 48, color: AppColors.error),
                          const SizedBox(height: 12),
                          Text(
                            'Failed to load attributes',
                            style: TextStyle(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            e.toString(),
                            style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          OutlinedButton.icon(
                            onPressed: () => ref
                                .read(serviceAttributesNotifierProvider
                                    .notifier)
                                .refresh(),
                            icon: const Icon(Icons.refresh_rounded,
                                size: 16),
                            label: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                    data: (attrs) {
                      if (attrs.isEmpty) {
                        return _EmptyState(onAdd: _openCreate);
                      }
                      return _AttributesTable(
                        attributes: attrs,
                        onEdit: _openEdit,
                        onDelete: _confirmDelete,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Table ──────────────────────────────────────────────────────────────────────

class _AttributesTable extends StatelessWidget {
  final List<ServiceAttribute> attributes;
  final void Function(ServiceAttribute) onEdit;
  final void Function(ServiceAttribute) onDelete;

  const _AttributesTable({
    required this.attributes,
    required this.onEdit,
    required this.onDelete,
  });

  static const double _minTableWidth = 550;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final tableWidth = constraints.maxWidth < _minTableWidth
                      ? _minTableWidth
                      : constraints.maxWidth;
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: tableWidth,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            color: AppColors.background,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            child: const Row(
                              children: [
                                _HeaderCell('Attribute Name', flex: 4),
                                _HeaderCell('Field Type', flex: 2),
                                _HeaderCell('Required', flex: 2),
                                _HeaderCell('Options', flex: 2),
                                _HeaderCell('Actions', flex: 3,
                                    align: TextAlign.center),
                              ],
                            ),
                          ),
                          const Divider(height: 1),
                          Expanded(
                            child: ListView.separated(
                              itemCount: attributes.length,
                              separatorBuilder: (_, i) =>
                                  const Divider(height: 1),
                              itemBuilder: (ctx, i) {
                                final attr = attributes[i];
                                return _AttributeRow(
                                  attribute: attr,
                                  onEdit: () => onEdit(attr),
                                  onDelete: () => onDelete(attr),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            Container(
              color: AppColors.background,
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 10),
              child: Text(
                '${attributes.length} attribute${attributes.length == 1 ? '' : 's'}',
                style: TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  final String label;
  final int flex;
  final TextAlign align;

  const _HeaderCell(this.label,
      {required this.flex, this.align = TextAlign.left});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Text(
        label,
        textAlign: align,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _AttributeRow extends StatelessWidget {
  final ServiceAttribute attribute;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _AttributeRow({
    required this.attribute,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final typeCfg = _typeConfig[attribute.fieldType] ??
        ('Unknown', AppColors.textSecondary);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          // Name
          Expanded(
            flex: 4,
            child: Text(
              attribute.name,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // Field type
          Expanded(
            flex: 2,
            child: _TypeBadge(label: typeCfg.$1, color: typeCfg.$2),
          ),

          // Required
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Icon(
                  attribute.isRequired
                      ? Icons.star_rounded
                      : Icons.star_border_rounded,
                  size: 16,
                  color: attribute.isRequired
                      ? AppColors.warning
                      : AppColors.textSecondary.withValues(alpha: 0.4),
                ),
                const SizedBox(width: 5),
                Text(
                  attribute.isRequired ? 'Yes' : 'No',
                  style: TextStyle(
                    fontSize: 13,
                    color: attribute.isRequired
                        ? AppColors.warning
                        : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),

          // Options count
          Expanded(
            flex: 2,
            child: attribute.hasOptions
                ? Text(
                    '${attribute.options.length} option${attribute.options.length == 1 ? '' : 's'}',
                    style: TextStyle(
                      fontSize: 13,
                      color: attribute.options.isEmpty
                          ? AppColors.error
                          : AppColors.textSecondary,
                    ),
                  )
                : Text(
                    '—',
                    style: TextStyle(
                        fontSize: 13, color: AppColors.textSecondary),
                  ),
          ),

          // Actions
          Expanded(
            flex: 3,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: onEdit,
                  icon: Icon(Icons.edit_rounded,
                      size: 16, color: AppColors.accent),
                  tooltip: 'Edit',
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  onPressed: onDelete,
                  icon: Icon(Icons.delete_outline_rounded,
                      size: 16, color: AppColors.error),
                  tooltip: 'Delete',
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TypeBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _TypeBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

// ── Empty / No-selection states ───────────────────────────────────────────────

class _NoServiceSelected extends StatelessWidget {
  const _NoServiceSelected();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.touch_app_rounded,
            size: 56,
            color: AppColors.textSecondary.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          Text(
            'Select a service',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Choose a service above to view and manage its attributes.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.tune_rounded,
            size: 56,
            color: AppColors.textSecondary.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          Text(
            'No attributes yet',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Click "New Attribute" to add the first one.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded, size: 16),
            label: const Text('New Attribute'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}
