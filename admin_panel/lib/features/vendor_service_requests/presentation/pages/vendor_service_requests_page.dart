import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/admin_search_bar.dart';
import '../../application/providers/vendor_service_requests_providers.dart';
import '../../domain/models/vendor_service_request.dart';
import '../widgets/service_request_detail_dialog.dart';

class VendorServiceRequestsPage extends ConsumerWidget {
  const VendorServiceRequestsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requestsAsync = ref.watch(vendorServiceRequestsNotifierProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──────────────────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Vendor Requests',
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                      ),
                      const SizedBox(height: 4),
                      requestsAsync.when(
                        loading: () => const SizedBox.shrink(),
                        error: (_, __) => const SizedBox.shrink(),
                        data: (all) {
                          final pending = all
                              .where((r) => r.isPending || r.isPendingDeletion)
                              .length;
                          return Text(
                            pending > 0
                                ? '$pending pending review'
                                : 'Manage vendor requests',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: pending > 0
                                      ? const Color(0xFFF59E0B)
                                      : AppColors.textSecondary,
                                  fontWeight: pending > 0
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded),
                  tooltip: 'Refresh',
                  onPressed: () => ref
                      .read(vendorServiceRequestsNotifierProvider.notifier)
                      .refresh(),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // ── Content ─────────────────────────────────────────────────────────
            const Expanded(child: _ServiceRequestsTab()),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Service Requests tab
// ─────────────────────────────────────────────────────────────────────────────

class _ServiceRequestsTab extends ConsumerStatefulWidget {
  const _ServiceRequestsTab();

  @override
  ConsumerState<_ServiceRequestsTab> createState() =>
      _ServiceRequestsTabState();
}

class _ServiceRequestsTabState extends ConsumerState<_ServiceRequestsTab> {
  String _filter = 'all';
  String _searchQuery = '';

  List<VendorServiceRequest> _applyFilters(List<VendorServiceRequest> all) {
    var list = all.toList();
    if (_filter != 'all') {
      list = list.where((r) => r.status == _filter).toList();
    }
    if (_searchQuery.isNotEmpty) {
      list = list
          .where((r) =>
              r.serviceName.toLowerCase().contains(_searchQuery) ||
              r.vendorName.toLowerCase().contains(_searchQuery))
          .toList();
    }
    return list;
  }

  void _openDetail(VendorServiceRequest r) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => ServiceRequestDetailDialog(request: r),
    );
  }

  @override
  Widget build(BuildContext context) {
    final requestsAsync = ref.watch(vendorServiceRequestsNotifierProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AdminSearchBar(
          hintText: 'Search by service or vendor name…',
          onChanged: (q) => setState(() => _searchQuery = q.toLowerCase()),
        ),
        const SizedBox(height: 12),
        _FilterChips(
          filters: const [
            ('pending', 'Pending'),
            ('needs_catalog', 'Needs Catalog'),
            ('completed', 'Completed'),
            ('rejected', 'Rejected'),
            ('all', 'All'),
          ],
          selected: _filter,
          counts: requestsAsync.whenOrNull(
            data: (all) => {
              'all': all.length,
              'pending': all.where((r) => r.isPending).length,
              'needs_catalog': all.where((r) => r.isNeedsCatalog).length,
              'completed': all.where((r) => r.isCompleted).length,
              'rejected': all.where((r) => r.isRejected).length,
            },
          ),
          onSelect: (f) => setState(() => _filter = f),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: requestsAsync.when(
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (e, _) =>
                Center(child: Text('Error loading requests: $e')),
            data: (all) {
              final list = _applyFilters(all);
              if (list.isEmpty) {
                return _EmptyState(
                    filter: _filter,
                    query: _searchQuery,
                    emptyLabel: 'No service requests yet');
              }
              return _ServiceTable(list: list, onDetail: _openDetail);
            },
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Service Requests table
// ─────────────────────────────────────────────────────────────────────────────

class _ServiceTable extends StatelessWidget {
  const _ServiceTable({required this.list, required this.onDetail});

  final List<VendorServiceRequest> list;
  final ValueChanged<VendorServiceRequest> onDetail;

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
        child: SingleChildScrollView(
          child: DataTable(
            headingRowColor:
                WidgetStatePropertyAll(AppColors.background),
            dataRowMinHeight: 56,
            dataRowMaxHeight: 72,
            columns: const [
              DataColumn(label: Text('Vendor')),
              DataColumn(label: Text('Service Name')),
              DataColumn(label: Text('Price'), numeric: true),
              DataColumn(label: Text('Status')),
              DataColumn(label: Text('Submitted')),
              DataColumn(label: Text('Actions')),
            ],
            rows: list.map((r) {
              return DataRow(cells: [
                DataCell(Text(
                  r.vendorName,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w500),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                )),
                DataCell(
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.serviceName,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w500),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      _RequestTypeChip(label: r.requestTypeLabel),
                    ],
                  ),
                ),
                DataCell(Text(
                  r.isPriceChange ? r.formattedNewPrice : r.formattedPrice,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                )),
                DataCell(_StatusChip(status: r.status)),
                DataCell(Text(
                  r.formattedDate,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                )),
                DataCell(_ReviewButton(
                  label: 'View',
                  isPrimary: r.isPending || r.isNeedsCatalog || r.isPendingDeletion,
                  onTap: () => onDetail(r),
                )),
              ]);
            }).toList(),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared widgets
// ─────────────────────────────────────────────────────────────────────────────

class _ReviewButton extends StatelessWidget {
  const _ReviewButton({
    required this.label,
    required this.isPrimary,
    required this.onTap,
  });

  final String label;
  final bool isPrimary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        visualDensity: VisualDensity.compact,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: isPrimary ? AppColors.primary : AppColors.textSecondary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ── Filter chips ──────────────────────────────────────────────────────────────

class _FilterChips extends StatelessWidget {
  const _FilterChips({
    required this.filters,
    required this.selected,
    required this.counts,
    required this.onSelect,
  });

  final List<(String, String)> filters;
  final String selected;
  final Map<String, int>? counts;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: filters.map((entry) {
          final (key, label) = entry;
          final count = counts?[key];
          final isSelected = selected == key;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(
                count != null ? '$label ($count)' : label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white : AppColors.textSecondary,
                ),
              ),
              selected: isSelected,
              onSelected: (_) => onSelect(key),
              selectedColor: AppColors.primary,
              backgroundColor: AppColors.background,
              checkmarkColor: Colors.white,
              side: BorderSide(
                  color: isSelected ? AppColors.primary : AppColors.border),
              padding:
                  const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Status chip ───────────────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'needs_catalog' => ('Needs Catalog', AppColors.primary),
      'completed' => ('Completed', AppColors.success),
      'rejected' => ('Rejected', AppColors.error),
      'pending_deletion' => ('Pending Deletion', const Color(0xFFF59E0B)),
      'deleted' => ('Deleted', AppColors.error),
      _ => ('Pending', const Color(0xFFF59E0B)),
    };
    return _ChipContainer(label: label, color: color);
  }
}

class _ChipContainer extends StatelessWidget {
  const _ChipContainer({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _RequestTypeChip extends StatelessWidget {
  const _RequestTypeChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = switch (label) {
      'Price Change'                   => AppColors.primary,
      'Deletion' || 'Deletion Request' => AppColors.error,
      'Edit Proposal'                  => const Color(0xFFF59E0B),
      _                                => AppColors.success,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.filter,
    required this.query,
    required this.emptyLabel,
  });

  final String filter;
  final String query;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    final filterLabel = switch (filter) {
      'needs_catalog' => 'needs-catalog',
      _ => filter,
    };
    final message = query.isNotEmpty
        ? 'No requests match "$query"'
        : filter == 'all'
            ? emptyLabel
            : 'No $filterLabel requests';

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.inbox_outlined,
              size: 56, color: AppColors.textSecondary),
          const SizedBox(height: 12),
          Text(message, style: Theme.of(context).textTheme.titleMedium),
          if (filter == 'all' && query.isEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Vendor requests will appear here once submitted.',
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
}
