import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../application/providers/service_addons_providers.dart';
import '../../domain/models/service_addon.dart';
import 'addon_form_dialog.dart';

class ServiceAddonsDialog extends ConsumerStatefulWidget {
  final String serviceId;
  final String serviceName;

  const ServiceAddonsDialog({
    super.key,
    required this.serviceId,
    required this.serviceName,
  });

  @override
  ConsumerState<ServiceAddonsDialog> createState() =>
      _ServiceAddonsDialogState();
}

class _ServiceAddonsDialogState extends ConsumerState<ServiceAddonsDialog> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(serviceAddonsNotifierProvider.notifier)
          .loadForService(widget.serviceId);
    });
  }

  void _openNew() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AddonFormDialog(
        serviceId: widget.serviceId,
        serviceName: widget.serviceName,
        onSave: ({
          required serviceId,
          required name,
          description,
          required price,
          required isActive,
        }) =>
            ref.read(serviceAddonsNotifierProvider.notifier).create(
                  serviceId: serviceId,
                  name: name,
                  description: description,
                  price: price,
                  isActive: isActive,
                ),
      ),
    );
  }

  void _openEdit(ServiceAddon addon) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AddonFormDialog(
        existing: addon,
        serviceId: widget.serviceId,
        serviceName: widget.serviceName,
        onSave: ({
          required serviceId,
          required name,
          description,
          required price,
          required isActive,
        }) =>
            ref.read(serviceAddonsNotifierProvider.notifier).update(
                  addon.id,
                  name: name,
                  description: description,
                  price: price,
                  isActive: isActive,
                ),
      ),
    );
  }

  Future<void> _toggle(ServiceAddon addon) async {
    try {
      await ref
          .read(serviceAddonsNotifierProvider.notifier)
          .toggleActive(addon.id, isActive: !addon.isActive);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Update failed: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _delete(ServiceAddon addon) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Delete Add-on'),
        content: Text(
          'Are you sure you want to delete "${addon.name}"?\n\nThis action cannot be undone.',
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
          .read(serviceAddonsNotifierProvider.notifier)
          .delete(addon.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Add-on deleted')),
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
    final state = ref.watch(serviceAddonsNotifierProvider);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 560),
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
                  const Icon(
                    Icons.extension_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Manage Add-ons',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          widget.serviceName,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _openNew,
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: const Text('New Add-on'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.2),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      textStyle: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white70),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),

            // ── Body ────────────────────────────────────────────────────────
            Expanded(
              child: state.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline_rounded,
                          size: 40, color: AppColors.error),
                      const SizedBox(height: 10),
                      Text(
                        'Failed to load add-ons',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        e.toString(),
                        style: TextStyle(
                            fontSize: 12, color: AppColors.textSecondary),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 14),
                      OutlinedButton.icon(
                        onPressed: () => ref
                            .read(serviceAddonsNotifierProvider.notifier)
                            .refresh(),
                        icon: const Icon(Icons.refresh_rounded, size: 16),
                        label: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
                data: (addons) {
                  if (addons.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.extension_off_rounded,
                            size: 48,
                            color: AppColors.textSecondary
                                .withValues(alpha: 0.4),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'No add-ons yet',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Click "New Add-on" to create the first one.',
                            style: TextStyle(
                                fontSize: 13,
                                color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: addons.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _AddonRow(
                      addon: addons[i],
                      onEdit: () => _openEdit(addons[i]),
                      onToggle: () => _toggle(addons[i]),
                      onDelete: () => _delete(addons[i]),
                    ),
                  );
                },
              ),
            ),

            // ── Footer ──────────────────────────────────────────────────────
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(16)),
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  state.whenOrNull(
                        data: (a) => Text(
                          '${a.length} add-on${a.length == 1 ? '' : 's'}',
                          style: TextStyle(
                              fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ) ??
                      const SizedBox.shrink(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
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

class _AddonRow extends StatelessWidget {
  final ServiceAddon addon;
  final VoidCallback onEdit;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  const _AddonRow({
    required this.addon,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final priceStr = NumberFormat.currency(symbol: '₹', decimalDigits: 2)
        .format(addon.price);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          // Status indicator dot
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
              color: addon.isActive ? AppColors.success : AppColors.textSecondary,
              shape: BoxShape.circle,
            ),
          ),

          // Name + description
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  addon.name,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: addon.isActive
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                  ),
                ),
                if (addon.description != null &&
                    addon.description!.isNotEmpty)
                  Text(
                    addon.description!,
                    style: TextStyle(
                        fontSize: 11, color: AppColors.textSecondary),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),

          // Price
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              priceStr,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ),

          // Actions
          Transform.scale(
            scale: 0.8,
            child: Switch(
              value: addon.isActive,
              onChanged: (_) => onToggle(),
              activeThumbColor: AppColors.success,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
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
    );
  }
}
