import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../application/providers/vendor_detail_providers.dart';
import '../../domain/models/vendor.dart';
import '../../domain/models/vendor_detail.dart';

final _currencyFmt =
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);

class VendorDetailsPage extends ConsumerWidget {
  const VendorDetailsPage({super.key, required this.vendorId});
  final String vendorId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vendorAsync = ref.watch(vendorByIdProvider(vendorId));

    return vendorAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _ErrorView(
        message: e.toString(),
        onRetry: () => ref.invalidate(vendorByIdProvider(vendorId)),
      ),
      data: (vendor) => _VendorDetailView(vendor: vendor, vendorId: vendorId),
    );
  }
}

// ── Main view ──────────────────────────────────────────────────────────────────

class _VendorDetailView extends StatelessWidget {
  const _VendorDetailView({required this.vendor, required this.vendorId});
  final Vendor vendor;
  final String vendorId;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PageHeader(vendor: vendor),
            const SizedBox(height: 20),
            TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              indicatorColor: AppColors.accent,
              labelColor: AppColors.accent,
              unselectedLabelColor: AppColors.textSecondary,
              tabs: const [
                Tab(text: 'Overview'),
                Tab(text: 'Documents'),
                Tab(text: 'Service Areas'),
                Tab(text: 'Analytics'),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: TabBarView(
                children: [
                  _OverviewTab(vendor: vendor),
                  _DocumentsTab(vendorId: vendorId),
                  _ServiceAreasTab(vendorId: vendorId),
                  _AnalyticsTab(vendor: vendor, vendorId: vendorId),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Page header ────────────────────────────────────────────────────────────────

class _PageHeader extends StatelessWidget {
  const _PageHeader({required this.vendor});
  final Vendor vendor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => context.go('/dashboard/vendors'),
          borderRadius: BorderRadius.circular(4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.arrow_back_rounded,
                  size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 4),
              Text(
                'Vendors',
                style: TextStyle(
                    fontSize: 13, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: AppColors.primaryLight,
              backgroundImage: vendor.profileImageUrl != null
                  ? NetworkImage(vendor.profileImageUrl!)
                  : null,
              onBackgroundImageError:
                  vendor.profileImageUrl != null ? (_, _) {} : null,
              child: vendor.profileImageUrl == null
                  ? Text(
                      _initials(vendor.businessName),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    vendor.businessName,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (vendor.ownerName?.isNotEmpty ?? false)
                    Text(
                      vendor.ownerName!,
                      style: TextStyle(
                          fontSize: 13, color: AppColors.textSecondary),
                    ),
                ],
              ),
            ),
            _StatusChip(status: vendor.status),
          ],
        ),
      ],
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
}

// ── Overview Tab ───────────────────────────────────────────────────────────────

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.vendor});
  final Vendor vendor;

  @override
  Widget build(BuildContext context) {
    final dateStr = vendor.createdAt != null
        ? DateFormat('d MMM yyyy').format(vendor.createdAt!)
        : '—';
    final updatedStr = vendor.updatedAt != null
        ? DateFormat('d MMM yyyy').format(vendor.updatedAt!)
        : '—';

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle('Contact Information'),
          const SizedBox(height: 12),
          _InfoGrid(children: [
            _InfoCell(
                icon: Icons.phone_rounded, label: 'Phone', value: vendor.phone),
            _InfoCell(
                icon: Icons.email_rounded, label: 'Email', value: vendor.email),
            _InfoCell(
                icon: Icons.location_city_rounded,
                label: 'City',
                value: vendor.city),
            _InfoCell(
                icon: Icons.home_rounded,
                label: 'Address',
                value: vendor.address ?? '—'),
          ]),
          const SizedBox(height: 24),
          _SectionTitle('Business Details'),
          const SizedBox(height: 12),
          _InfoGrid(children: [
            _InfoCell(
              icon: Icons.toggle_on_rounded,
              label: 'Active',
              value: vendor.isActive ? 'Yes' : 'No',
              valueColor:
                  vendor.isActive ? AppColors.success : AppColors.textSecondary,
            ),
            _InfoCell(
              icon: Icons.star_rounded,
              label: 'Rating',
              value: vendor.rating?.toStringAsFixed(1) ?? 'No rating',
            ),
            _InfoCell(
              icon: Icons.account_balance_wallet_rounded,
              label: 'Wallet Balance',
              value: _currencyFmt.format(vendor.walletBalance),
              valueColor: AppColors.accent,
            ),
            _InfoCell(
                icon: Icons.calendar_today_rounded,
                label: 'Joined',
                value: dateStr),
            _InfoCell(
                icon: Icons.update_rounded,
                label: 'Last Updated',
                value: updatedStr),
          ]),
        ],
      ),
    );
  }
}

class _InfoGrid extends StatelessWidget {
  const _InfoGrid({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: children,
    );
  }
}

class _InfoCell extends StatelessWidget {
  const _InfoCell({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: AppColors.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                      fontSize: 11, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: valueColor ?? AppColors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Documents Tab ──────────────────────────────────────────────────────────────

class _DocumentsTab extends ConsumerStatefulWidget {
  const _DocumentsTab({required this.vendorId});
  final String vendorId;

  @override
  ConsumerState<_DocumentsTab> createState() => _DocumentsTabState();
}

class _DocumentsTabState extends ConsumerState<_DocumentsTab> {
  final Set<String> _loading = {};

  Future<void> _updateStatus(String docId, String status) async {
    setState(() => _loading.add(docId));
    try {
      await ref
          .read(vendorDetailRepositoryProvider)
          .updateDocumentStatus(docId, status);
      ref.invalidate(vendorDocumentsProvider(widget.vendorId));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Document ${status == 'approved' ? 'approved' : 'rejected'}.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading.remove(docId));
    }
  }

  void _viewDocument(VendorDocument doc) {
    showDialog(
      context: context,
      builder: (_) => _DocumentViewDialog(doc: doc),
    );
  }

  @override
  Widget build(BuildContext context) {
    final docsAsync = ref.watch(vendorDocumentsProvider(widget.vendorId));

    return docsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _ErrorView(
        message: 'Failed to load documents: $e',
        onRetry: () =>
            ref.invalidate(vendorDocumentsProvider(widget.vendorId)),
      ),
      data: (docs) {
        if (docs.isEmpty) {
          return _EmptyTabState(
            icon: Icons.folder_open_rounded,
            message: 'No documents uploaded',
            sub: 'The vendor has not uploaded any documents yet.',
          );
        }
        return ListView.separated(
          itemCount: docs.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (_, i) {
            final doc = docs[i];
            return _DocumentCard(
              doc: doc,
              isLoading: _loading.contains(doc.id),
              onApprove: () => _updateStatus(doc.id, 'approved'),
              onReject: () => _updateStatus(doc.id, 'rejected'),
              onView: () => _viewDocument(doc),
            );
          },
        );
      },
    );
  }
}

class _DocumentCard extends StatelessWidget {
  const _DocumentCard({
    required this.doc,
    required this.isLoading,
    required this.onApprove,
    required this.onReject,
    required this.onView,
  });

  final VendorDocument doc;
  final bool isLoading;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onView;

  @override
  Widget build(BuildContext context) {
    final dateStr = doc.createdAt != null
        ? DateFormat('d MMM yyyy').format(doc.createdAt!)
        : null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.description_rounded,
                color: AppColors.primary, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  doc.displayName,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (dateStr != null)
                  Text(
                    'Uploaded $dateStr',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _DocStatusBadge(status: doc.verificationStatus),
          const SizedBox(width: 12),
          if (isLoading)
            const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2))
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton.icon(
                  onPressed: onView,
                  icon: const Icon(Icons.visibility_rounded, size: 14),
                  label: const Text('View'),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                ),
                const SizedBox(width: 8),
                if (doc.verificationStatus != 'approved')
                  FilledButton.icon(
                    onPressed: onApprove,
                    icon: const Icon(Icons.check_rounded, size: 14),
                    label: const Text('Approve'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.success,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                  ),
                if (doc.verificationStatus != 'rejected') ...[
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: onReject,
                    icon: const Icon(Icons.close_rounded, size: 14),
                    label: const Text('Reject'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: BorderSide(color: AppColors.error),
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

class _DocStatusBadge extends StatelessWidget {
  const _DocStatusBadge({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, color, bg) = switch (status) {
      'approved' => ('Approved', AppColors.success, const Color(0xFFF0FFF4)),
      'rejected' => ('Rejected', AppColors.error, const Color(0xFFFFF5F5)),
      _ => ('Pending', AppColors.warning, const Color(0xFFFEEBC8)),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
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

class _DocumentViewDialog extends StatelessWidget {
  const _DocumentViewDialog({required this.doc});
  final VendorDocument doc;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints:
            const BoxConstraints(maxWidth: 700, maxHeight: 600),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      doc.displayName,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () async {
                      await Clipboard.setData(
                          ClipboardData(text: doc.documentUrl));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('URL copied to clipboard')),
                        );
                      }
                    },
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    tooltip: 'Copy URL',
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(12)),
                child: InteractiveViewer(
                  child: Image.network(
                    doc.documentUrl,
                    fit: BoxFit.contain,
                    loadingBuilder: (_, child, progress) => progress == null
                        ? child
                        : const Center(
                            child: CircularProgressIndicator()),
                    errorBuilder: (_, _, _) => Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.broken_image_rounded,
                              size: 48, color: AppColors.textSecondary),
                          const SizedBox(height: 12),
                          Text(
                            'Cannot preview this file.',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                          const SizedBox(height: 8),
                          SelectableText(
                            doc.documentUrl,
                            style: TextStyle(
                                fontSize: 12,
                                color: AppColors.accent),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Service Areas Tab ──────────────────────────────────────────────────────────

class _ServiceAreasTab extends ConsumerWidget {
  const _ServiceAreasTab({required this.vendorId});
  final String vendorId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final areasAsync = ref.watch(vendorServiceAreasProvider(vendorId));

    return areasAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _ErrorView(
        message: 'Failed to load service areas: $e',
        onRetry: () => ref.invalidate(vendorServiceAreasProvider(vendorId)),
      ),
      data: (areas) {
        if (areas.isEmpty) {
          return const _EmptyTabState(
            icon: Icons.map_rounded,
            message: 'No service areas configured',
            sub: 'The vendor has not set up any service areas yet.',
          );
        }
        return ListView.separated(
          itemCount: areas.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (_, i) {
            final a = areas[i];
            return Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.location_on_rounded,
                        size: 18, color: AppColors.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          a.city,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        if (a.area?.isNotEmpty ?? false)
                          Text(a.area!,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                  if (a.pincode?.isNotEmpty ?? false)
                    _Chip(text: a.pincode!,
                        color: AppColors.textSecondary),
                  if (a.radiusKm != null) ...[
                    const SizedBox(width: 8),
                    _Chip(
                      text: '${a.radiusKm!.toStringAsFixed(1)} km',
                      color: AppColors.accent,
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600, color: color)),
    );
  }
}

// ── Analytics Tab ──────────────────────────────────────────────────────────────

class _AnalyticsTab extends ConsumerWidget {
  const _AnalyticsTab({required this.vendor, required this.vendorId});
  final Vendor vendor;
  final String vendorId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(vendorBookingStatsProvider(vendorId));

    return statsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _ErrorView(
        message: 'Failed to load analytics: $e',
        onRetry: () =>
            ref.invalidate(vendorBookingStatsProvider(vendorId)),
      ),
      data: (stats) => SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionTitle('Booking Statistics'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _StatCard(
                    label: 'Total',
                    value: '${stats.total}',
                    icon: Icons.calendar_month_rounded,
                    color: AppColors.primary),
                _StatCard(
                    label: 'Pending',
                    value: '${stats.pending}',
                    icon: Icons.schedule_rounded,
                    color: AppColors.warning),
                _StatCard(
                    label: 'Assigned',
                    value: '${stats.assigned}',
                    icon: Icons.assignment_rounded,
                    color: AppColors.accent),
                _StatCard(
                    label: 'In Progress',
                    value: '${stats.inProgress}',
                    icon: Icons.handyman_rounded,
                    color: const Color(0xFF805AD5)),
                _StatCard(
                    label: 'Completed',
                    value: '${stats.completed}',
                    icon: Icons.check_circle_rounded,
                    color: AppColors.success),
                _StatCard(
                    label: 'Rejected',
                    value: '${stats.rejected}',
                    icon: Icons.cancel_rounded,
                    color: AppColors.error),
                _StatCard(
                    label: 'Cancelled',
                    value: '${stats.cancelled}',
                    icon: Icons.block_rounded,
                    color: AppColors.textSecondary),
              ],
            ),
            const SizedBox(height: 24),
            _SectionTitle('Earnings & Settlement'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _StatCard(
                  label: 'Total Earnings',
                  value: _currencyFmt.format(stats.totalEarnings),
                  icon: Icons.payments_rounded,
                  color: AppColors.success,
                  wide: true,
                ),
                _StatCard(
                  label: 'Wallet Balance',
                  value: _currencyFmt.format(vendor.walletBalance),
                  icon: Icons.account_balance_wallet_rounded,
                  color: AppColors.accent,
                  wide: true,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.wide = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: wide ? 240 : 160,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: color),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style:
                TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

// ── Shared helpers ─────────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
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
      'active' => ('Active', AppColors.success),
      'inactive' => ('Inactive', AppColors.textSecondary),
      'suspended' => ('Suspended', AppColors.error),
      _ => ('Pending', AppColors.warning),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _EmptyTabState extends StatelessWidget {
  const _EmptyTabState({
    required this.icon,
    required this.message,
    required this.sub,
  });
  final IconData icon;
  final String message;
  final String sub;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 52, color: AppColors.textSecondary.withValues(alpha: 0.5)),
          const SizedBox(height: 14),
          Text(
            message,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            sub,
            style:
                TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline_rounded, size: 48, color: AppColors.error),
          const SizedBox(height: 12),
          Text(
            message,
            style:
                TextStyle(fontSize: 13, color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
