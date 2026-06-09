import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../application/providers/customers_providers.dart';
import '../../domain/models/customer.dart';
import '../widgets/customer_details_dialog.dart';
import '../widgets/customer_edit_dialog.dart';

final _dateFmtShort = DateFormat('dd MMM yyyy');

// ── Filter enum ───────────────────────────────────────────────────────────────

enum _StatusFilter { all, active, inactive }

// ── Page ──────────────────────────────────────────────────────────────────────

class CustomersPage extends ConsumerStatefulWidget {
  const CustomersPage({super.key});

  @override
  ConsumerState<CustomersPage> createState() => _CustomersPageState();
}

class _CustomersPageState extends ConsumerState<CustomersPage> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  _StatusFilter _statusFilter = _StatusFilter.all;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ── Filtering ──────────────────────────────────────────────────────────────

  List<Customer> _applyFilters(List<Customer> all) {
    var result = all;
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      result = result
          .where((c) =>
              c.fullName.toLowerCase().contains(q) ||
              c.phone.toLowerCase().contains(q) ||
              c.email.toLowerCase().contains(q))
          .toList();
    }
    switch (_statusFilter) {
      case _StatusFilter.active:
        result = result.where((c) => c.isActive).toList();
      case _StatusFilter.inactive:
        result = result.where((c) => !c.isActive).toList();
      case _StatusFilter.all:
        break;
    }
    return result;
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  void _openDetails(Customer c) {
    showDialog(
      context: context,
      builder: (_) => CustomerDetailsDialog(customer: c),
    );
  }

  void _openEdit(Customer c) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => CustomerEditDialog(
        customer: c,
        onSave: ({
          required fullName,
          required phone,
          required email,
          profileImageUrl,
          required isActive,
        }) async {
          await ref
              .read(customersNotifierProvider.notifier)
              .updateCustomer(
                c.id,
                fullName: fullName,
                phone: phone,
                email: email,
                profileImageUrl: profileImageUrl,
                isActive: isActive,
              );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('Customer updated successfully')),
            );
          }
        },
      ),
    );
  }

  Future<void> _toggleActive(Customer c) async {
    try {
      await ref
          .read(customersNotifierProvider.notifier)
          .toggleActive(c.id, currentIsActive: c.isActive);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              c.isActive
                  ? '${c.fullName} deactivated'
                  : '${c.fullName} activated',
            ),
          ),
        );
      }
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

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(customersNotifierProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ────────────────────────────────────────────────────────
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Customers',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Manage customer accounts and profiles',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Stats cards ───────────────────────────────────────────────────
          state.when(
            loading: () => const SizedBox.shrink(),
            error: (e, st) => const SizedBox.shrink(),
            data: (all) => _StatsRow(customers: all),
          ),

          const SizedBox(height: 16),

          // ── Search + Filters ──────────────────────────────────────────────
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 280,
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search by name, phone or email…',
                    prefixIcon:
                        const Icon(Icons.search_rounded, size: 18),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded,
                                size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                  ),
                  onChanged: (v) =>
                      setState(() => _searchQuery = v.trim()),
                ),
              ),
              _FilterChip(
                label: 'All',
                selected: _statusFilter == _StatusFilter.all,
                onTap: () =>
                    setState(() => _statusFilter = _StatusFilter.all),
              ),
              _FilterChip(
                label: 'Active',
                selected: _statusFilter == _StatusFilter.active,
                color: AppColors.success,
                onTap: () =>
                    setState(() => _statusFilter = _StatusFilter.active),
              ),
              _FilterChip(
                label: 'Inactive',
                selected: _statusFilter == _StatusFilter.inactive,
                color: AppColors.error,
                onTap: () => setState(
                    () => _statusFilter = _StatusFilter.inactive),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Body ──────────────────────────────────────────────────────────
          Expanded(
            child: state.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline_rounded,
                        size: 48, color: AppColors.error),
                    const SizedBox(height: 12),
                    Text('Failed to load customers',
                        style: TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Text(e.toString(),
                        style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13),
                        textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () => ref
                          .read(customersNotifierProvider.notifier)
                          .refresh(),
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
              data: (all) {
                final filtered = _applyFilters(all);
                if (all.isEmpty) {
                  return const _EmptyState(
                    message: 'No customers yet',
                    sub:
                        'Customers will appear here once they register on the platform.',
                  );
                }
                if (filtered.isEmpty) {
                  return const _EmptyState(
                    message: 'No customers match your filters',
                    sub: 'Try adjusting your search or filters.',
                  );
                }
                return _CustomersTable(
                  customers: filtered,
                  totalCount: all.length,
                  onViewDetails: _openDetails,
                  onEdit: _openEdit,
                  onToggleActive: _toggleActive,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Stats row ─────────────────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  final List<Customer> customers;

  const _StatsRow({required this.customers});

  @override
  Widget build(BuildContext context) {
    final total = customers.length;
    final active = customers.where((c) => c.isActive).length;
    final inactive = total - active;

    return Row(
      children: [
        _StatCard(
          label: 'Total Customers',
          value: '$total',
          icon: Icons.people_rounded,
          color: AppColors.primary,
        ),
        const SizedBox(width: 12),
        _StatCard(
          label: 'Active',
          value: '$active',
          icon: Icons.check_circle_rounded,
          color: AppColors.success,
        ),
        const SizedBox(width: 12),
        _StatCard(
          label: 'Inactive',
          value: '$inactive',
          icon: Icons.cancel_rounded,
          color: AppColors.error,
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 20, color: color),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Filter chip ───────────────────────────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    this.color = AppColors.primary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.1)
              : AppColors.background,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? color.withValues(alpha: 0.5)
                : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: selected ? color : AppColors.textSecondary,
            fontWeight:
                selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

// ── Table ─────────────────────────────────────────────────────────────────────

class _CustomersTable extends StatelessWidget {
  final List<Customer> customers;
  final int totalCount;
  final void Function(Customer) onViewDetails;
  final void Function(Customer) onEdit;
  final void Function(Customer) onToggleActive;

  const _CustomersTable({
    required this.customers,
    required this.totalCount,
    required this.onViewDetails,
    required this.onEdit,
    required this.onToggleActive,
  });

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
            // Header row
            Container(
              color: AppColors.background,
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 12),
              child: const Row(
                children: [
                  SizedBox(width: 48),
                  _HCell('Customer', flex: 4),
                  _HCell('Phone', flex: 3),
                  _HCell('Email', flex: 4),
                  _HCell('Status', flex: 2),
                  _HCell('Joined', flex: 2),
                  _HCell('Actions', flex: 2, align: TextAlign.center),
                ],
              ),
            ),
            const Divider(height: 1),
            // Data rows
            Expanded(
              child: ListView.separated(
                itemCount: customers.length,
                separatorBuilder: (ctx, i) => const Divider(height: 1),
                itemBuilder: (ctx, i) {
                  return _CustomerRow(
                    customer: customers[i],
                    onViewDetails: () => onViewDetails(customers[i]),
                    onEdit: () => onEdit(customers[i]),
                    onToggleActive: () =>
                        onToggleActive(customers[i]),
                  );
                },
              ),
            ),
            // Footer
            Container(
              color: AppColors.background,
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 10),
              child: Text(
                customers.length == totalCount
                    ? '${customers.length} customer${customers.length == 1 ? '' : 's'}'
                    : '${customers.length} of $totalCount customer${totalCount == 1 ? '' : 's'}',
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

class _HCell extends StatelessWidget {
  final String label;
  final int flex;
  final TextAlign align;

  const _HCell(this.label,
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

class _CustomerRow extends StatelessWidget {
  final Customer customer;
  final VoidCallback onViewDetails;
  final VoidCallback onEdit;
  final VoidCallback onToggleActive;

  const _CustomerRow({
    required this.customer,
    required this.onViewDetails,
    required this.onEdit,
    required this.onToggleActive,
  });

  @override
  Widget build(BuildContext context) {
    final c = customer;
    final joinedStr =
        c.createdAt != null ? _dateFmtShort.format(c.createdAt!) : '—';

    return Padding(
      padding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          // Avatar
          SizedBox(
            width: 48,
            child: _RowAvatar(
                imageUrl: c.profileImageUrl, name: c.fullName),
          ),

          // Full Name
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.fullName.isEmpty ? '—' : c.fullName,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          // Phone
          Expanded(
            flex: 3,
            child: Text(
              c.phone.isEmpty ? '—' : c.phone,
              style: TextStyle(
                  fontSize: 13, color: AppColors.textSecondary),
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // Email
          Expanded(
            flex: 4,
            child: Text(
              c.email.isEmpty ? '—' : c.email,
              style: TextStyle(
                  fontSize: 13, color: AppColors.textSecondary),
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // Status badge
          Expanded(
            flex: 2,
            child: _StatusBadge(isActive: c.isActive),
          ),

          // Joined date
          Expanded(
            flex: 2,
            child: Text(
              joinedStr,
              style: TextStyle(
                  fontSize: 12, color: AppColors.textSecondary),
            ),
          ),

          // Actions
          Expanded(
            flex: 2,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: onViewDetails,
                  icon: const Icon(Icons.visibility_rounded, size: 16),
                  tooltip: 'View Details',
                  color: AppColors.textSecondary,
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_rounded, size: 16),
                  tooltip: 'Edit',
                  color: AppColors.accent,
                  visualDensity: VisualDensity.compact,
                ),
                Tooltip(
                  message:
                      c.isActive ? 'Deactivate' : 'Activate',
                  child: IconButton(
                    onPressed: onToggleActive,
                    icon: Icon(
                      c.isActive
                          ? Icons.toggle_on_rounded
                          : Icons.toggle_off_rounded,
                      size: 20,
                      color: c.isActive
                          ? AppColors.success
                          : AppColors.textSecondary,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RowAvatar extends StatelessWidget {
  final String? imageUrl;
  final String name;

  const _RowAvatar({this.imageUrl, required this.name});

  @override
  Widget build(BuildContext context) {
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return CircleAvatar(
        radius: 16,
        backgroundImage: NetworkImage(imageUrl!),
        backgroundColor: AppColors.border,
        onBackgroundImageError: (e, st) {},
      );
    }
    return CircleAvatar(
      radius: 16,
      backgroundColor: AppColors.primary.withValues(alpha: 0.1),
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: AppColors.primary,
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final bool isActive;

  const _StatusBadge({required this.isActive});

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isActive
              ? AppColors.success.withValues(alpha: 0.1)
              : AppColors.error.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          isActive ? 'Active' : 'Inactive',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: isActive ? AppColors.success : AppColors.error,
          ),
        ),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final String message;
  final String sub;

  const _EmptyState({required this.message, required this.sub});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.people_outline_rounded,
            size: 56,
            color: AppColors.textSecondary.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(sub,
              style: TextStyle(
                  fontSize: 13, color: AppColors.textSecondary),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
