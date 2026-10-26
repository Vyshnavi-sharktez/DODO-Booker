import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/admin_search_bar.dart';
import '../../application/providers/service_addons_providers.dart';
import '../../domain/models/service_addon.dart';
import '../widgets/addon_form_dialog.dart';
import '../widgets/addon_linked_services_dialog.dart';
import '../../../bulk_upload/data/modules/addon_bulk_module.dart';
import '../../../bulk_upload/presentation/bulk_upload_dialog.dart';

class AddonsPage extends ConsumerStatefulWidget {
  const AddonsPage({super.key});

  @override
  ConsumerState<AddonsPage> createState() => _AddonsPageState();
}

class _AddonsPageState extends ConsumerState<AddonsPage> {
  String _searchQuery = '';
  static final _currency =
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

  List<ServiceAddon> _filtered(List<ServiceAddon> all) {
    if (_searchQuery.isEmpty) return all;
    return all
        .where((a) => a.name.toLowerCase().contains(_searchQuery))
        .toList();
  }

  void _openCreate() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AddonFormDialog(
        onSave: ({
          required name,
          description,
          required price,
          required isActive,
          isGlobal = false,
          discountType = 'percentage',
          discountValue = 0,
        }) =>
            ref.read(allAddonsNotifierProvider.notifier).create(
                  name: name,
                  description: description,
                  price: price,
                  isActive: isActive,
                  isGlobal: isGlobal,
                  discountType: discountType,
                  discountValue: discountValue,
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
        onSave: ({
          required name,
          description,
          required price,
          required isActive,
          isGlobal = false,
          discountType = 'percentage',
          discountValue = 0,
        }) =>
            ref.read(allAddonsNotifierProvider.notifier).update(
                  addon.id,
                  name: name,
                  description: description,
                  price: price,
                  isActive: isActive,
                  isGlobal: isGlobal,
                  discountType: discountType,
                  discountValue: discountValue,
                ),
      ),
    );
  }

  void _openView(ServiceAddon addon) {
    showDialog(
      context: context,
      builder: (_) => AddonLinkedServicesDialog(addon: addon),
    );
  }

  Future<void> _confirmDelete(ServiceAddon addon) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Delete Add-on?'),
        content: Text(
          'Delete "${addon.name}"? This also unlinks it from all services.',
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
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(allAddonsNotifierProvider.notifier).delete(addon.id);
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
    final addonsAsync = ref.watch(allAddonsNotifierProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ────────────────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Add-ons',
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Global add-ons appear across all categories. Service add-ons are linked from the Catalog.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                      ),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => BulkUploadDialog.show(
                    context,
                    AddonBulkModule(),
                    onComplete: () => ref
                        .read(allAddonsNotifierProvider.notifier)
                        .refresh(),
                  ),
                  icon: const Icon(Icons.upload_file_rounded, size: 16),
                  label: const Text('Bulk Upload'),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: _openCreate,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('New Add-on'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // ── Search ────────────────────────────────────────────────────────
            AdminSearchBar(
              hintText: 'Search add-ons…',
              onChanged: (q) => setState(() => _searchQuery = q.toLowerCase()),
            ),
            const SizedBox(height: 16),

            // ── Tables ────────────────────────────────────────────────────────
            Expanded(
              child: addonsAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) =>
                    Center(child: Text('Error loading add-ons: $e')),
                data: (allAddons) {
                  final filtered = _filtered(allAddons);
                  final globals =
                      filtered.where((a) => a.isGlobal).toList();
                  final specific =
                      filtered.where((a) => !a.isGlobal).toList();

                  if (filtered.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.extension_off_rounded,
                              size: 56, color: AppColors.textSecondary),
                          const SizedBox(height: 12),
                          Text(
                            _searchQuery.isEmpty
                                ? 'No add-ons yet'
                                : 'No add-ons match "$_searchQuery"',
                            style:
                                Theme.of(context).textTheme.titleMedium,
                          ),
                          if (_searchQuery.isEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Click "New Add-on" and enable "Global Add-on" to create one.',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                      color: AppColors.textSecondary),
                            ),
                          ],
                        ],
                      ),
                    );
                  }

                  return SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Global section ─────────────────────────────────
                        _SectionHeader(
                          icon: Icons.public_rounded,
                          title: 'Global Add-ons',
                          count: globals.length,
                          color: AppColors.primary,
                          subtitle:
                              'Displayed across all service categories',
                        ),
                        const SizedBox(height: 8),
                        if (globals.isEmpty)
                          _EmptySection(
                            message:
                                'No global add-ons. Toggle "Global Add-on" when creating.',
                          )
                        else
                          _AddonTable(
                            addons: globals,
                            currency: _currency,
                            onEdit: _openEdit,
                            onDelete: _confirmDelete,
                            onToggle: (id, val) => ref
                                .read(allAddonsNotifierProvider.notifier)
                                .toggleActive(id, isActive: val),
                            showGlobalBadge: false,
                          ),

                        const SizedBox(height: 28),

                        // ── Service-specific section ───────────────────────
                        _SectionHeader(
                          icon: Icons.build_circle_outlined,
                          title: 'Service Add-ons',
                          count: specific.length,
                          color: AppColors.textSecondary,
                          subtitle:
                              'Linked to specific services from the Catalog',
                        ),
                        const SizedBox(height: 8),
                        if (specific.isEmpty)
                          _EmptySection(
                            message:
                                'No service-specific add-ons. Create one and link it from the Catalog.',
                          )
                        else
                          _AddonTable(
                            addons: specific,
                            currency: _currency,
                            onEdit: _openEdit,
                            onDelete: _confirmDelete,
                            onView: _openView,
                            onToggle: (id, val) => ref
                                .read(allAddonsNotifierProvider.notifier)
                                .toggleActive(id, isActive: val),
                            showGlobalBadge: false,
                          ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Section header ─────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final int count;
  final Color color;
  final String subtitle;

  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.count,
    required this.color,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
        ),
        const SizedBox(width: 8),
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            subtitle,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
        ),
      ],
    );
  }
}

// ── Empty state for a section ──────────────────────────────────────────────────

class _EmptySection extends StatelessWidget {
  final String message;
  const _EmptySection({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: AppColors.border, style: BorderStyle.solid),
      ),
      child: Text(
        message,
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: AppColors.textSecondary),
        textAlign: TextAlign.center,
      ),
    );
  }
}

// ── Shared add-on table ────────────────────────────────────────────────────────

class _AddonTable extends StatelessWidget {
  final List<ServiceAddon> addons;
  final NumberFormat currency;
  final void Function(ServiceAddon) onEdit;
  final void Function(ServiceAddon) onDelete;
  final void Function(ServiceAddon)? onView;
  final void Function(String id, bool val) onToggle;
  final bool showGlobalBadge;

  const _AddonTable({
    required this.addons,
    required this.currency,
    required this.onEdit,
    required this.onDelete,
    this.onView,
    required this.onToggle,
    this.showGlobalBadge = true,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: DataTable(
          headingRowColor:
              WidgetStatePropertyAll(AppColors.background),
          columns: [
            const DataColumn(label: Text('Name')),
            if (showGlobalBadge)
              const DataColumn(label: Text('Scope')),
            const DataColumn(label: Text('Price'), numeric: true),
            const DataColumn(label: Text('Status')),
            const DataColumn(label: Text('Actions')),
          ],
          rows: addons.map((addon) {
            return DataRow(cells: [
              DataCell(
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      addon.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 13,
                      ),
                    ),
                    if (addon.description != null &&
                        addon.description!.isNotEmpty)
                      Text(
                        addon.description!,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              if (showGlobalBadge)
                DataCell(
                  addon.isGlobal
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.primary
                                .withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'All Services',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        )
                      : Text(
                          '—',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                ),
              DataCell(
                Text(
                  currency.format(addon.price),
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
              DataCell(
                Switch(
                  value: addon.isActive,
                  onChanged: (val) => onToggle(addon.id, val),
                  activeColor: AppColors.success,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              DataCell(
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (onView != null)
                      IconButton(
                        icon: const Icon(Icons.visibility_outlined,
                            size: 16),
                        tooltip: 'View linked services',
                        color: AppColors.primary,
                        visualDensity: VisualDensity.compact,
                        onPressed: () => onView!(addon),
                      ),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      tooltip: 'Edit',
                      color: AppColors.textSecondary,
                      visualDensity: VisualDensity.compact,
                      onPressed: () => onEdit(addon),
                    ),
                    IconButton(
                      icon:
                          const Icon(Icons.delete_outline, size: 16),
                      tooltip: 'Delete',
                      color: AppColors.error,
                      visualDensity: VisualDensity.compact,
                      onPressed: () => onDelete(addon),
                    ),
                  ],
                ),
              ),
            ]);
          }).toList(),
        ),
      ),
    );
  }
}
