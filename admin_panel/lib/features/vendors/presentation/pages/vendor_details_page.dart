import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/admin_back_button.dart';
import '../../../vendor_settlement/application/providers/vendor_settlement_providers.dart';
import '../../application/providers/vendor_detail_providers.dart';
import '../../application/providers/vendors_providers.dart';
import '../../data/vendors_repository.dart';
import '../../domain/models/vendor.dart';
import '../../domain/models/vendor_detail.dart';
import '../../domain/models/vendor_penalty_record.dart';
import '../widgets/manual_penalty_dialog.dart';
import '../widgets/vendor_form_dialog.dart';
import '../widgets/vendor_wallet_history_dialog.dart';

final _currencyFmt =
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);

class VendorDetailsPage extends ConsumerWidget {
  const VendorDetailsPage({super.key, required this.vendorId, this.initialTab = 0});
  final String vendorId;
  final int initialTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vendorAsync = ref.watch(vendorByIdProvider(vendorId));

    return vendorAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _ErrorView(
        message: e.toString(),
        onRetry: () => ref.invalidate(vendorByIdProvider(vendorId)),
      ),
      data: (vendor) => _VendorDetailView(vendor: vendor, vendorId: vendorId, initialTab: initialTab),
    );
  }
}

// ── Main view ──────────────────────────────────────────────────────────────────

class _VendorDetailView extends ConsumerWidget {
  const _VendorDetailView({required this.vendor, required this.vendorId, required this.initialTab});
  final Vendor vendor;
  final String vendorId;
  final int initialTab;

  Future<void> _openApplyPenalty(BuildContext context, WidgetRef ref) async {
    await showDialog<void>(
      context: context,
      builder: (_) => ManualPenaltyDialog(
        vendorId: vendorId,
        vendorName: vendor.businessName,
        onSuccess: () => ref.invalidate(vendorByIdProvider(vendorId)),
      ),
    );
  }

  Future<void> _openEdit(BuildContext context, WidgetRef ref) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => VendorFormDialog(
        existing: vendor,
        onSave: ({
          required businessName,
          ownerName,
          required phone,
          required email,
          required city,
          address,
          required status,
          required isActive,
          rating,
          latitude,
          longitude,
          commissionRate,
          required isPreferredVendor,
          required preferredVendorFee,
        }) async {
          await ref.read(vendorsNotifierProvider.notifier).updateVendor(
                vendorId,
                businessName: businessName,
                ownerName: ownerName,
                phone: phone,
                email: email,
                city: city,
                address: address,
                status: status,
                isActive: isActive,
                rating: rating,
                latitude: latitude,
                longitude: longitude,
                commissionRate: commissionRate,
                isPreferredVendor: isPreferredVendor,
                preferredVendorFee: preferredVendorFee,
              );
          ref.invalidate(vendorByIdProvider(vendorId));
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 5,
      initialIndex: initialTab.clamp(0, 4),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PageHeader(
              vendor: vendor,
              onEdit: () => _openEdit(context, ref),
              onApplyPenalty: () => _openApplyPenalty(context, ref),
            ),
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
                Tab(text: 'Analytics'),
                Tab(text: 'Penalty History'),
                Tab(text: 'Services'),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: TabBarView(
                children: [
                  _OverviewTab(vendor: vendor),
                  _DocumentsTab(vendorId: vendorId),
                  _AnalyticsTab(vendor: vendor, vendorId: vendorId),
                  _PenaltyHistoryTab(vendorId: vendorId),
                  _ServicesTab(vendorId: vendorId),
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
  const _PageHeader({
    required this.vendor,
    required this.onEdit,
    required this.onApplyPenalty,
  });
  final Vendor vendor;
  final VoidCallback onEdit;
  final VoidCallback onApplyPenalty;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AdminBackButton(
          label: 'Vendors',
          onTap: () => context.canPop()
              ? context.pop()
              : context.go('/dashboard/vendors'),
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
                  if (vendor.vendorNumber != null) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withAlpha(20),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: AppColors.primary.withAlpha(60), width: 1),
                      ),
                      child: Text(
                        vendor.vendorNumber!,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            _StatusChip(status: vendor.status),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: onApplyPenalty,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.error,
                side: const BorderSide(color: AppColors.error),
              ),
              icon: const Icon(Icons.gavel_rounded, size: 16),
              label: const Text('Charge Penalty'),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: onEdit,
              icon: Icon(Icons.edit_rounded, size: 18, color: AppColors.primary),
              tooltip: 'Edit Vendor',
            ),
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

class _OverviewTab extends ConsumerWidget {
  const _OverviewTab({required this.vendor});
  final Vendor vendor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                label: 'Business Address',
                value: vendor.address ?? '—'),
          ]),
          const SizedBox(height: 24),
          _SectionTitle('Vendor Tier & Performance'),
          const SizedBox(height: 12),
          _VendorPerformanceSection(vendor: vendor),
          const SizedBox(height: 24),
          _SectionTitle('Business Details'),
          const SizedBox(height: 12),
          _InfoGrid(children: [
            if (vendor.vendorNumber != null)
              _InfoCell(
                icon: Icons.tag_rounded,
                label: 'Vendor ID',
                value: vendor.vendorNumber!,
              ),
            _InfoCell(
              icon: Icons.check_circle_outline_rounded,
              label: 'Account Active',
              value: vendor.isActive ? 'Yes' : 'No',
              valueColor:
                  vendor.isActive ? AppColors.success : AppColors.textSecondary,
            ),
            _InfoCell(
              icon: Icons.wifi_rounded,
              label: 'Online (Vendor-controlled)',
              value: vendor.isOnline ? 'Online' : 'Offline',
              valueColor:
                  vendor.isOnline ? AppColors.success : AppColors.textSecondary,
            ),
            _InfoCell(
              icon: Icons.star_rounded,
              label: 'Rating',
              value: vendor.rating?.toStringAsFixed(1) ?? 'No rating',
            ),
            _InfoCell(
              icon: Icons.workspace_premium_rounded,
              label: 'Preferred Vendor',
              value: vendor.isPreferredVendor ? 'Yes' : 'No',
              valueColor: vendor.isPreferredVendor
                  ? AppColors.success
                  : AppColors.textSecondary,
            ),
            if (vendor.isPreferredVendor) ...[
              _InfoCell(
                icon: Icons.currency_rupee_rounded,
                label: 'Preferred Fee (Normal)',
                value: vendor.preferredVendorFee > 0
                    ? '₹${vendor.preferredVendorFee.toStringAsFixed(2)}'
                    : '—',
              ),
            ],
            Builder(builder: (context) {
              final pendingAsync =
                  ref.watch(vendorPendingSettlementProvider(vendor.id));
              return _InfoCell(
                icon: Icons.pending_actions_rounded,
                label: 'Pending Settlement',
                value: pendingAsync.when(
                  loading: () => '…',
                  error: (_, __) => '—',
                  data: (s) => s != null
                      ? _currencyFmt.format(s.pendingSettlement)
                      : '—',
                ),
                valueColor: AppColors.warning,
              );
            }),
            _InfoCell(
                icon: Icons.calendar_today_rounded,
                label: 'Joined',
                value: dateStr),
            _InfoCell(
                icon: Icons.update_rounded,
                label: 'Last Updated',
                value: updatedStr),
          ]),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _SectionTitle('Wallet Information'),
              OutlinedButton.icon(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (_) => VendorWalletHistoryDialog(
                      vendorId: vendor.id,
                      vendorName: vendor.businessName,
                    ),
                  );
                },
                icon: const Icon(Icons.history_rounded, size: 16),
                label: const Text('View Wallet History'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Builder(
            builder: (context) {
              final walletInfoAsync =
                  ref.watch(vendorWalletInfoProvider(vendor.id));
              return walletInfoAsync.when(
                loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(),
                  ),
                ),
                error: (err, _) => Text(
                  'Failed to load wallet info: $err',
                  style: const TextStyle(color: AppColors.error, fontSize: 12),
                ),
                data: (info) {
                  final lastTopUpStr =
                      info.lastTopUpAmount != null && info.lastTopUpDate != null
                          ? '₹${info.lastTopUpAmount!.toStringAsFixed(2)} on ${DateFormat('d MMM yyyy').format(info.lastTopUpDate!)}'
                          : '—';

                  return _InfoGrid(
                    children: [
                      _InfoCell(
                        icon: Icons.account_balance_wallet_rounded,
                        label: 'Available Balance',
                        value: _currencyFmt.format(info.availableBalance),
                        valueColor: info.isEligible
                            ? AppColors.success
                            : AppColors.error,
                      ),
                      _InfoCell(
                        icon: Icons.hourglass_empty_rounded,
                        label: 'Pending Balance',
                        value: _currencyFmt.format(info.pendingBalance),
                        valueColor: AppColors.warning,
                      ),
                      _InfoCell(
                        icon: Icons.shield_rounded,
                        label: 'Minimum Required Balance',
                        value: _currencyFmt.format(info.minimumRequiredBalance),
                      ),
                      _InfoCell(
                        icon: info.isEligible
                            ? Icons.check_circle_rounded
                            : Icons.warning_rounded,
                        label: 'Wallet Status',
                        value: info.statusLabel,
                        valueColor: info.isEligible
                            ? AppColors.success
                            : AppColors.error,
                      ),
                      _InfoCell(
                        icon: Icons.add_card_rounded,
                        label: 'Last Top-Up',
                        value: lastTopUpStr,
                      ),
                    ],
                  );
                },
              );
            },
          ),
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

// ── Analytics Tab ──────────────────────────────────────────────────────────────

class _AnalyticsTab extends ConsumerWidget {
  const _AnalyticsTab({required this.vendor, required this.vendorId});
  final Vendor vendor;
  final String vendorId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(vendorBookingStatsProvider(vendorId));
    final pendingAsync = ref.watch(vendorPendingSettlementProvider(vendorId));

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
                  label: 'Pending Settlement',
                  value: pendingAsync.when(
                    loading: () => '…',
                    error: (_, __) => '—',
                    data: (s) => s != null
                        ? _currencyFmt.format(s.pendingSettlement)
                        : '—',
                  ),
                  icon: Icons.pending_actions_rounded,
                  color: AppColors.warning,
                  wide: true,
                ),
                _StatCard(
                  label: 'Total Settled',
                  value: pendingAsync.when(
                    loading: () => '…',
                    error: (_, __) => '—',
                    data: (s) => s != null
                        ? _currencyFmt.format(s.totalPaid)
                        : '—',
                  ),
                  icon: Icons.payments_rounded,
                  color: AppColors.success,
                  wide: true,
                ),
                _StatCard(
                  label: 'Last Settlement Date',
                  value: pendingAsync.when(
                    loading: () => '…',
                    error: (_, __) => '—',
                    data: (s) => s?.lastSettlementAt != null
                        ? DateFormat('dd MMM yyyy').format(s!.lastSettlementAt!)
                        : '—',
                  ),
                  icon: Icons.event_available_rounded,
                  color: AppColors.primary,
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

// ── Penalty History Tab ────────────────────────────────────────────────────────

class _PenaltyHistoryTab extends ConsumerWidget {
  const _PenaltyHistoryTab({required this.vendorId});
  final String vendorId;

  static final _dateTimeFmt = DateFormat('dd MMM yyyy, hh:mm a');

  void _viewPenaltyDetails(BuildContext context, VendorPenaltyRecord record) {
    showDialog<void>(
      context: context,
      builder: (_) => _PenaltyDetailsDialog(record: record),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(vendorPenaltyHistoryProvider(vendorId));

    return historyAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _ErrorView(
        message: 'Failed to load penalty history: $e',
        onRetry: () => ref.invalidate(vendorPenaltyHistoryProvider(vendorId)),
      ),
      data: (penalties) {
        if (penalties.isEmpty) {
          return const _EmptyTabState(
            icon: Icons.gavel_rounded,
            message: 'No penalty history found',
            sub: 'This vendor has no penalty deductions on record.',
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionTitle('Penalty Ledger (${penalties.length})'),
            const SizedBox(height: 12),
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return SingleChildScrollView(
                        scrollDirection: Axis.vertical,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minWidth: constraints.maxWidth,
                            ),
                            child: DataTable(
                              headingRowColor:
                                  WidgetStateProperty.all(AppColors.background),
                              columnSpacing: 24,
                              columns: const [
                                DataColumn(
                                    label: Text('Date & Time', softWrap: false)),
                                DataColumn(
                                    label: Text('Type', softWrap: false)),
                                DataColumn(
                                    label: Text('Amount', softWrap: false)),
                                DataColumn(
                                    label: Text('Reason', softWrap: false)),
                                DataColumn(
                                    label: Text('Reference', softWrap: false)),
                                DataColumn(
                                    label: Text('Applied By', softWrap: false)),
                                DataColumn(
                                    label: Text('Balance (Before → After)',
                                        softWrap: false)),
                                DataColumn(
                                    label: Text('Action', softWrap: false)),
                              ],
                              rows: penalties.map((p) {
                                return DataRow(cells: [
                                  DataCell(Text(
                                    _dateTimeFmt.format(p.createdAt),
                                    style: const TextStyle(fontSize: 12),
                                    softWrap: false,
                                  )),
                                  DataCell(_PenaltyTypeBadge(isManual: p.isManual)),
                                  DataCell(Text(
                                    '₹${p.amount.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.error,
                                    ),
                                    softWrap: false,
                                  )),
                                  DataCell(Text(
                                    p.description ?? '—',
                                    style: const TextStyle(fontSize: 12),
                                    overflow: TextOverflow.ellipsis,
                                  )),
                                  DataCell(Text(
                                    p.isManual
                                        ? (p.description?.isNotEmpty == true
                                            ? p.description!
                                            : '—')
                                        : (p.bookingNumber != null
                                            ? '#${p.bookingNumber}'
                                            : (p.referenceId != null &&
                                                    p.referenceId!.length >= 8
                                                ? '#${p.referenceId!.substring(0, 8)}'
                                                : '—')),
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontFamily: p.isManual ? null : 'monospace',
                                    ),
                                    softWrap: false,
                                    overflow: TextOverflow.ellipsis,
                                  )),
                                  DataCell(Text(
                                    p.appliedBy,
                                    style: const TextStyle(fontSize: 12),
                                    softWrap: false,
                                  )),
                                  DataCell(Text(
                                    '₹${p.balanceBefore.toStringAsFixed(2)} → ₹${p.balanceAfter.toStringAsFixed(2)}',
                                    style: const TextStyle(fontSize: 12),
                                    softWrap: false,
                                  )),
                                  DataCell(
                                    OutlinedButton.icon(
                                      onPressed: () =>
                                          _viewPenaltyDetails(context, p),
                                      icon: const Icon(Icons.visibility_rounded,
                                          size: 14),
                                      label: const Text('View Details'),
                                      style: OutlinedButton.styleFrom(
                                        visualDensity: VisualDensity.compact,
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 6),
                                        textStyle:
                                            const TextStyle(fontSize: 12),
                                      ),
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
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PenaltyTypeBadge extends StatelessWidget {
  const _PenaltyTypeBadge({required this.isManual});
  final bool isManual;

  @override
  Widget build(BuildContext context) {
    final color = isManual ? AppColors.warning : AppColors.error;
    final label = isManual ? 'Manual' : 'Automatic';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
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

class _PenaltyDetailsDialog extends StatelessWidget {
  const _PenaltyDetailsDialog({required this.record});
  final VendorPenaltyRecord record;

  static final _dateTimeFmt = DateFormat('dd MMM yyyy, hh:mm a');

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.gavel_rounded,
                      color: AppColors.error,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Penalty Details',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          _dateTimeFmt.format(record.createdAt),
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, size: 20),
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Divider(color: AppColors.border),
              const SizedBox(height: 14),

              // Banner Amount Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.error.withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Amount Deducted',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '₹${record.amount.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: AppColors.error,
                          ),
                        ),
                      ],
                    ),
                    _PenaltyTypeBadge(isManual: record.isManual),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Details Grid
              _DetailRow(label: 'Reason', value: record.description ?? '—'),
              _DetailRow(label: 'Applied By', value: record.appliedBy),
              _DetailRow(
                label: 'Wallet Balance Before',
                value: '₹${record.balanceBefore.toStringAsFixed(2)}',
              ),
              _DetailRow(
                label: 'Wallet Balance After',
                value: '₹${record.balanceAfter.toStringAsFixed(2)}',
              ),
              if (record.bookingNumber != null || record.referenceId != null)
                _DetailRow(
                  label: 'Booking Ref',
                  value: record.bookingNumber != null
                      ? '#${record.bookingNumber}'
                      : (record.referenceId != null && record.referenceId!.length >= 8
                          ? '#${record.referenceId!.substring(0, 8)}'
                          : '—'),
                ),
              if (record.serviceName != null)
                _DetailRow(label: 'Linked Service', value: record.serviceName!),

              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Services Tab ───────────────────────────────────────────────────────────────

// ── Category colour palette (matches Vendor App) ─────────────────────────────
const _kAdminCatColors = [
  Color(0xFF4A90D9),
  Color(0xFFE67E22),
  Color(0xFF27AE60),
  Color(0xFF8E44AD),
  Color(0xFFE74C3C),
  Color(0xFF16A085),
  Color(0xFFF39C12),
  Color(0xFF2980B9),
  Color(0xFFC0392B),
  Color(0xFF1ABC9C),
];

IconData _adminIconForCategory(String name) {
  final n = name.toLowerCase();
  if (n.contains('clean')) return Icons.cleaning_services_rounded;
  if (n.contains('ac') || n.contains('appliance')) return Icons.ac_unit_rounded;
  if (n.contains('plumb')) return Icons.plumbing_rounded;
  if (n.contains('pest')) return Icons.bug_report_rounded;
  if (n.contains('electric')) return Icons.electrical_services_rounded;
  if (n.contains('carpen')) return Icons.carpenter_rounded;
  if (n.contains('paint')) return Icons.format_paint_rounded;
  if (n.contains('garden') || n.contains('lawn')) return Icons.yard_rounded;
  if (n.contains('security') || n.contains('cctv')) return Icons.security_rounded;
  if (n.contains('repair') || n.contains('fix')) return Icons.build_rounded;
  return Icons.home_repair_service_rounded;
}

// ── Catalog tree helpers (identical logic to Vendor App) ─────────────────────

List<String> _adminAncestorPath(String? parentName, Map<String, String?> parentOf) {
  if (parentName == null) return const [];
  final path = <String>[];
  String? current = parentName;
  for (int i = 0; i < 20 && current != null; i++) {
    path.insert(0, current);
    current = parentOf[current];
  }
  return path;
}

class _AdminNode {
  _AdminNode(this.name);
  final String name;
  final Map<String, _AdminNode> children = {};
  final List<VendorPlatformService> leafServices = [];
  int get totalCount =>
      leafServices.length + children.values.fold(0, (s, n) => s + n.totalCount);
}

_AdminNode _buildAdminServicesTree(
    List<VendorPlatformService> services, Map<String, String?> parentOf) {
  final root = _AdminNode('__root__');
  for (final svc in services) {
    final path = _adminAncestorPath(svc.parentName, parentOf);
    var node = root;
    for (final segment in path) {
      node = node.children.putIfAbsent(segment, () => _AdminNode(segment));
    }
    node.leafServices.add(svc);
  }
  return root;
}

// ── Services Tab ─────────────────────────────────────────────────────────────

class _ServicesTab extends ConsumerWidget {
  const _ServicesTab({required this.vendorId});
  final String vendorId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servicesAsync = ref.watch(vendorPlatformServicesProvider(vendorId));
    final parentOf = ref.watch(adminCatalogParentMapProvider).valueOrNull ?? const {};

    return servicesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _ErrorView(
        message: 'Failed to load services: $e',
        onRetry: () => ref.invalidate(vendorPlatformServicesProvider(vendorId)),
      ),
      data: (services) {
        if (services.isEmpty) {
          return const _EmptyTabState(
            icon: Icons.home_repair_service_outlined,
            message: 'No platform services added',
            sub: 'This vendor has not added any services from the app catalog.',
          );
        }

        final tree = _buildAdminServicesTree(services, parentOf);
        final rootEntries = tree.children.entries.toList()
          ..sort((a, b) {
            if (a.key == 'Other') return 1;
            if (b.key == 'Other') return -1;
            return a.key.compareTo(b.key);
          });

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: rootEntries.length,
          itemBuilder: (_, i) {
            final entry = rootEntries[i];
            final catColor = _kAdminCatColors[i % _kAdminCatColors.length];
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _AdminTreeSection(
                node: entry.value,
                catColor: catColor,
                depth: 0,
              ),
            );
          },
        );
      },
    );
  }
}

// ── Recursive tree section (mirrors _MyWideTreeSection, read-only) ───────────

class _AdminTreeSection extends StatefulWidget {
  const _AdminTreeSection({
    required this.node,
    required this.catColor,
    required this.depth,
    this.isLast = false,
  });

  final _AdminNode node;
  final Color catColor;
  final int depth;
  final bool isLast;

  @override
  State<_AdminTreeSection> createState() => _AdminTreeSectionState();
}

class _AdminTreeSectionState extends State<_AdminTreeSection> {
  bool _expanded = false;

  List<_AdminNode> get _sortedChildren {
    final entries = widget.node.children.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return entries.map((e) => e.value).toList();
  }

  Widget _buildContent() {
    final node = widget.node;
    final children = _sortedChildren;
    final hasLeaves = node.leafServices.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (int i = 0; i < children.length; i++)
          _AdminTreeSection(
            node: children[i],
            catColor: widget.catColor,
            depth: widget.depth + 1,
            isLast: i == children.length - 1 && !hasLeaves,
          ),
        if (hasLeaves) ...[
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              children: [
                Expanded(flex: 3, child: _ColHeader('SERVICE NAME')),
                Expanded(flex: 2, child: _ColHeader('CATEGORY')),
                SizedBox(width: 110, child: _ColHeader('BASE PRICE')),
                SizedBox(width: 80, child: _ColHeader('STATUS')),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          for (int i = 0; i < node.leafServices.length; i++) ...[
            _AdminServiceRow(service: node.leafServices[i]),
            if (i < node.leafServices.length - 1)
              const Divider(
                  height: 1,
                  color: AppColors.border,
                  indent: 20,
                  endIndent: 20),
          ],
          const SizedBox(height: 4),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final node = widget.node;
    final totalCount = node.totalCount;

    if (widget.depth == 0) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: widget.catColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(_adminIconForCategory(node.name),
                          size: 17, color: widget.catColor),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        node.name,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    Text(
                      '$totalCount service${totalCount == 1 ? '' : 's'}',
                      style: const TextStyle(
                          fontSize: 12.5, color: AppColors.textSecondary),
                    ),
                    const SizedBox(width: 12),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: const Icon(Icons.keyboard_arrow_down_rounded,
                          size: 20, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
            if (_expanded) ...[
              const Divider(height: 1, color: AppColors.border),
              _buildContent(),
            ],
          ],
        ),
      );
    }

    // Depth > 0: inline inside parent card
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                SizedBox(width: (widget.depth - 1) * 12.0),
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: AppColors.textSecondary,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    node.name,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                Text(
                  '$totalCount service${totalCount == 1 ? '' : 's'}',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                ),
                const SizedBox(width: 10),
                AnimatedRotation(
                  turns: _expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(Icons.keyboard_arrow_down_rounded,
                      size: 18, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ),
        if (_expanded) ...[
          const Divider(height: 1, color: AppColors.border),
          _buildContent(),
        ],
        if (!widget.isLast) const Divider(height: 1, color: AppColors.border),
      ],
    );
  }
}

class _AdminServiceRow extends StatelessWidget {
  const _AdminServiceRow({required this.service});
  final VendorPlatformService service;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              service.name,
              style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              service.parentName ?? '—',
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textSecondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(
            width: 110,
            child: Text(
              service.basePrice > 0
                  ? '₹${service.basePrice.toStringAsFixed(0)}'
                  : '—',
              style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary),
            ),
          ),
          SizedBox(
            width: 80,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: (service.isActive
                        ? AppColors.success
                        : AppColors.textSecondary)
                    .withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                service.isActive ? 'Active' : 'Inactive',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: service.isActive
                      ? AppColors.success
                      : AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── _ColHeader (shared with both sections) ────────────────────────────────────

class _ColHeader extends StatelessWidget {
  const _ColHeader(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: AppColors.textSecondary,
        letterSpacing: 0.5,
      ),
    );
  }
}

class _VendorPerformanceSection extends ConsumerStatefulWidget {
  final Vendor vendor;
  const _VendorPerformanceSection({required this.vendor});

  @override
  ConsumerState<_VendorPerformanceSection> createState() =>
      _VendorPerformanceSectionState();
}

class _VendorPerformanceSectionState
    extends ConsumerState<_VendorPerformanceSection> {
  bool _evaluating = false;

  Future<void> _reevaluateTier() async {
    setState(() => _evaluating = true);
    try {
      await ref
          .read(vendorsRepositoryProvider)
          .evaluateVendorPerformance(widget.vendor.id);
      ref.invalidate(vendorByIdProvider(widget.vendor.id));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Vendor tier re-evaluated successfully.'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to evaluate vendor performance: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _evaluating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.vendor;
    final tier = v.vendorTier;
    final evalTime = v.tierEvaluatedAt != null
        ? DateFormat('dd MMM yyyy, hh:mm a').format(v.tierEvaluatedAt!)
        : 'Never evaluated';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  if (tier != null) ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: tier.color.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                        border:
                            Border.all(color: tier.color.withValues(alpha: 0.4)),
                      ),
                      child: Icon(tier.iconData, color: tier.color, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tier.name,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: tier.color,
                          ),
                        ),
                        Text(
                          'Priority Rank #${tier.priority}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.border),
                      ),
                      child: const Icon(Icons.workspace_premium_rounded,
                          color: AppColors.textSecondary, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Unranked Vendor',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          'Evaluated: $evalTime',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 38),
                ),
                onPressed: _evaluating ? null : _reevaluateTier,
                icon: _evaluating
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync_rounded, size: 16),
                label: const Text('Recalculate Tier'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 16),

          // Live Metrics Async Loader
          FutureBuilder<VendorPerformanceMetrics>(
            future: ref
                .read(vendorsRepositoryProvider)
                .getVendorPerformanceMetrics(v.id),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: CircularProgressIndicator(),
                  ),
                );
              }
              if (snapshot.hasError) {
                return Text(
                  'Error loading metrics: ${snapshot.error}',
                  style:
                      const TextStyle(color: AppColors.error, fontSize: 12),
                );
              }

              final metrics = snapshot.data!;
              return _InfoGrid(children: [
                _InfoCell(
                  icon: Icons.check_circle_rounded,
                  label: 'Completed Orders',
                  value: '${metrics.completedBookings}',
                ),
                _InfoCell(
                  icon: Icons.star_rounded,
                  label: 'Average Rating',
                  value: '${metrics.avgRating.toStringAsFixed(1)} ★',
                ),
                _InfoCell(
                  icon: Icons.cancel_rounded,
                  label: 'Cancellation Rate',
                  value: '${metrics.cancellationRate.toStringAsFixed(1)}%',
                ),
                _InfoCell(
                  icon: Icons.task_alt_rounded,
                  label: 'Completion Rate',
                  value: '${metrics.completionRate.toStringAsFixed(1)}%',
                ),
              ]);
            },
          ),
        ],
      ),
    );
  }
}

