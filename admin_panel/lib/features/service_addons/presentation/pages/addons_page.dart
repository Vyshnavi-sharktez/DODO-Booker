import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/admin_search_bar.dart';
import '../../application/providers/service_addons_providers.dart';
import '../../domain/models/service_addon.dart';
import '../widgets/addon_form_dialog.dart';
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
          serviceId,
          discountType = 'percentage',
          discountValue = 0,
        }) =>
            ref.read(allAddonsNotifierProvider.notifier).create(
                  name: name,
                  description: description,
                  price: price,
                  isActive: isActive,
                  serviceId: serviceId,
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
          serviceId,
          discountType = 'percentage',
          discountValue = 0,
        }) =>
            ref.read(allAddonsNotifierProvider.notifier).update(
                  addon.id,
                  name: name,
                  description: description,
                  price: price,
                  isActive: isActive,
                  serviceId: serviceId,
                  discountType: discountType,
                  discountValue: discountValue,
                ),
      ),
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
                        'Create reusable add-ons. Link them to services from the Catalog.',
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

            // ── Table ─────────────────────────────────────────────────────────
            Expanded(
              child: addonsAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error loading add-ons: $e')),
                data: (allAddons) {
                  final list = _filtered(allAddons);
                  if (list.isEmpty) {
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
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          if (_searchQuery.isEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Click "New Add-on" to create the first one.',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: AppColors.textSecondary),
                            ),
                          ],
                        ],
                      ),
                    );
                  }

                  return Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(color: AppColors.border),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SingleChildScrollView(
                        child: DataTable(
                          headingRowColor: WidgetStatePropertyAll(
                              AppColors.background),
                          columns: const [
                            DataColumn(label: Text('Name')),
                            DataColumn(label: Text('Service')),
                            DataColumn(
                                label: Text('Price'), numeric: true),
                            DataColumn(label: Text('Status')),
                            DataColumn(label: Text('Actions')),
                          ],
                          rows: list.map((addon) {
                            return DataRow(cells: [
                              DataCell(
                                Column(
                                  mainAxisAlignment:
                                      MainAxisAlignment.center,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
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
                              DataCell(
                                addon.serviceId != null
                                    ? Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: AppColors.primary
                                              .withValues(alpha: 0.08),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          addon.serviceId!.substring(0, 8),
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: AppColors.primary,
                                            fontWeight: FontWeight.w500,
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
                                  _currency.format(addon.price),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              DataCell(
                                Switch(
                                  value: addon.isActive,
                                  onChanged: (val) => ref
                                      .read(allAddonsNotifierProvider
                                          .notifier)
                                      .toggleActive(addon.id,
                                          isActive: val),
                                  activeColor: AppColors.success,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                              ),
                              DataCell(
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(
                                          Icons.edit_outlined,
                                          size: 16),
                                      tooltip: 'Edit',
                                      color: AppColors.textSecondary,
                                      visualDensity:
                                          VisualDensity.compact,
                                      onPressed: () =>
                                          _openEdit(addon),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                          Icons.delete_outline,
                                          size: 16),
                                      tooltip: 'Delete',
                                      color: AppColors.error,
                                      visualDensity:
                                          VisualDensity.compact,
                                      onPressed: () =>
                                          _confirmDelete(addon),
                                    ),
                                  ],
                                ),
                              ),
                            ]);
                          }).toList(),
                        ),
                      ),
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
