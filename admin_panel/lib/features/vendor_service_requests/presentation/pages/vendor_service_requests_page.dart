import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/admin_search_bar.dart';
import '../../../../core/widgets/pagination_bar.dart';
import '../../application/providers/vendor_service_requests_providers.dart';
import '../../domain/models/vendor_service_request.dart';
import '../widgets/service_request_detail_dialog.dart';

class VendorServiceRequestsPage extends ConsumerStatefulWidget {
  const VendorServiceRequestsPage({super.key});

  @override
  ConsumerState<VendorServiceRequestsPage> createState() =>
      _VendorServiceRequestsPageState();
}

class _VendorServiceRequestsPageState
    extends ConsumerState<VendorServiceRequestsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final requestsAsync = ref.watch(vendorServiceRequestsNotifierProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──────────────────────────────────────────────────────
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

            // ── Top tabs ────────────────────────────────────────────────────
            Container(
              decoration: const BoxDecoration(
                border: Border(
                    bottom: BorderSide(color: AppColors.border, width: 0.8)),
              ),
              child: TabBar(
                controller: _tabController,
                labelColor: AppColors.primary,
                unselectedLabelColor: AppColors.textSecondary,
                indicatorColor: AppColors.primary,
                indicatorWeight: 2.5,
                labelStyle: const TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w600),
                unselectedLabelStyle:
                    const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500),
                tabs: [
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.storefront_rounded, size: 16),
                        const SizedBox(width: 6),
                        const Text('Custom Services'),
                        const SizedBox(width: 6),
                        requestsAsync.whenOrNull(
                          data: (all) {
                            final c = all
                                .where((r) =>
                                    !r.isInstaHelp &&
                                    (r.isPending || r.isPendingDeletion))
                                .length;
                            if (c == 0) return null;
                            return _TabBadge(count: c);
                          },
                        ) ?? const SizedBox.shrink(),
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.flash_on_rounded, size: 16),
                        const SizedBox(width: 6),
                        const Text('InstaHelp Services'),
                        const SizedBox(width: 6),
                        requestsAsync.whenOrNull(
                          data: (all) {
                            final c = all
                                .where((r) =>
                                    r.isInstaHelp && r.isPending)
                                .length;
                            if (c == 0) return null;
                            return _TabBadge(count: c);
                          },
                        ) ?? const SizedBox.shrink(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Tab content ─────────────────────────────────────────────────
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: const [
                  _RequestsTab(isInstaHelp: false),
                  _RequestsTab(isInstaHelp: true),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Generic tab (Custom Services or InstaHelp)
// ─────────────────────────────────────────────────────────────────────────────

class _RequestsTab extends ConsumerStatefulWidget {
  const _RequestsTab({required this.isInstaHelp});
  final bool isInstaHelp;

  @override
  ConsumerState<_RequestsTab> createState() => _RequestsTabState();
}

class _RequestsTabState extends ConsumerState<_RequestsTab>
    with AutomaticKeepAliveClientMixin {
  String _filter = 'all';
  String _searchQuery = '';
  int _page = 1;
  static const int _pageSize = 10;

  @override
  bool get wantKeepAlive => true;

  List<VendorServiceRequest> _applyFilters(List<VendorServiceRequest> all) {
    var list = all
        .where((r) => widget.isInstaHelp ? r.isInstaHelp : !r.isInstaHelp)
        .toList();
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
    super.build(context);
    final requestsAsync = ref.watch(vendorServiceRequestsNotifierProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AdminSearchBar(
          hintText: widget.isInstaHelp
              ? 'Search by mode or vendor name…'
              : 'Search by service or vendor name…',
          onChanged: (q) =>
              setState(() { _searchQuery = q.toLowerCase(); _page = 1; }),
        ),
        const SizedBox(height: 12),
        _FilterChips(
          filters: const [
            ('pending', 'Pending'),
            ('completed', 'Completed'),
            ('rejected', 'Rejected'),
            ('all', 'All'),
          ],
          selected: _filter,
          counts: requestsAsync.whenOrNull(
            data: (all) {
              final subset = all
                  .where((r) =>
                      widget.isInstaHelp ? r.isInstaHelp : !r.isInstaHelp)
                  .toList();
              return {
                'all': subset.length,
                'pending': subset.where((r) => r.isPending).length,
                'completed': subset.where((r) => r.isCompleted).length,
                'rejected': subset.where((r) => r.isRejected).length,
              };
            },
          ),
          onSelect: (f) => setState(() { _filter = f; _page = 1; }),
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
                return _EmptyState(filter: _filter, query: _searchQuery);
              }
              final paged = list
                  .skip((_page - 1) * _pageSize)
                  .take(_pageSize)
                  .toList();
              return Column(
                children: [
                  Expanded(
                    child: widget.isInstaHelp
                        ? _InstaHelpTable(list: paged, onDetail: _openDetail)
                        : _CustomServiceTable(list: paged, onDetail: _openDetail),
                  ),
                  PaginationBar(
                    totalItems: list.length,
                    currentPage: _page,
                    pageSize: _pageSize,
                    onPageChanged: (p) => setState(() => _page = p),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Custom Services table
// ─────────────────────────────────────────────────────────────────────────────

class _CustomServiceTable extends StatelessWidget {
  const _CustomServiceTable({required this.list, required this.onDetail});
  final List<VendorServiceRequest> list;
  final ValueChanged<VendorServiceRequest> onDetail;

  @override
  Widget build(BuildContext context) {
    return _TableCard(
      child: LayoutBuilder(
        builder: (context, constraints) => SizedBox(
          width: constraints.maxWidth,
          child: DataTable(
            headingRowColor: WidgetStatePropertyAll(AppColors.background),
            dataRowMinHeight: 56,
            dataRowMaxHeight: 72,
            columnSpacing: 24,
            horizontalMargin: 20,
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
                  isPrimary:
                      r.isPending || r.isNeedsCatalog || r.isPendingDeletion,
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
// InstaHelp table
// ─────────────────────────────────────────────────────────────────────────────

class _InstaHelpTable extends StatelessWidget {
  const _InstaHelpTable({required this.list, required this.onDetail});
  final List<VendorServiceRequest> list;
  final ValueChanged<VendorServiceRequest> onDetail;

  @override
  Widget build(BuildContext context) {
    return _TableCard(
      child: LayoutBuilder(
        builder: (context, constraints) => SizedBox(
          width: constraints.maxWidth,
          child: DataTable(
            headingRowColor: WidgetStatePropertyAll(AppColors.background),
            dataRowMinHeight: 56,
            dataRowMaxHeight: 72,
            columnSpacing: 24,
            horizontalMargin: 20,
            columns: const [
              DataColumn(label: Text('Vendor')),
              DataColumn(label: Text('Mode')),
              DataColumn(label: Text('Request Type')),
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
                DataCell(Text(
                  r.serviceName,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w500),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                )),
                DataCell(_RequestTypeChip(label: r.requestTypeLabel)),
                DataCell(_StatusChip(status: r.status)),
                DataCell(Text(
                  r.formattedDate,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                )),
                DataCell(_ReviewButton(
                  isPrimary: r.isPending,
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

class _TableCard extends StatelessWidget {
  const _TableCard({required this.child});
  final Widget child;

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
        child: SingleChildScrollView(child: child),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared widgets
// ─────────────────────────────────────────────────────────────────────────────

class _TabBadge extends StatelessWidget {
  const _TabBadge({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: const Color(0xFFF59E0B),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        '$count',
        style: const TextStyle(
            fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white),
      ),
    );
  }
}

class _ReviewButton extends StatelessWidget {
  const _ReviewButton({required this.isPrimary, required this.onTap});
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
        'View',
        style: TextStyle(
          fontSize: 12,
          color: isPrimary ? AppColors.primary : AppColors.textSecondary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

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
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'needs_catalog'   => ('Needs Catalog', AppColors.primary),
      'completed'       => ('Completed', AppColors.success),
      'rejected'        => ('Rejected', AppColors.error),
      'pending_deletion'=> ('Pending Deletion', const Color(0xFFF59E0B)),
      'deleted'         => ('Deleted', AppColors.error),
      _                 => ('Pending', const Color(0xFFF59E0B)),
    };
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
            fontSize: 11, fontWeight: FontWeight.w600, color: color),
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
      'Price Change'                                   => AppColors.primary,
      'Deletion' || 'Deletion Request' ||
      'Delete Duration' || 'Delete Activity'           => AppColors.error,
      'Edit Proposal' || 'Edit Duration' ||
      'Edit Activity' || 'Slot Config' ||
      'Financial Config'                               => const Color(0xFFF59E0B),
      _                                                => AppColors.success,
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
            fontSize: 10, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.filter, required this.query});
  final String filter;
  final String query;

  @override
  Widget build(BuildContext context) {
    final message = query.isNotEmpty
        ? 'No requests match "$query"'
        : filter == 'all'
            ? 'No requests yet'
            : 'No ${filter == 'needs_catalog' ? 'needs-catalog' : filter} requests';

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
