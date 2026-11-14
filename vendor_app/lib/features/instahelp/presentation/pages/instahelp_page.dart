import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/vendor_scaffold.dart';
import '../../../auth/presentation/providers/auth_controller.dart';
import '../../domain/models/instahelp_duration.dart';
import '../../domain/models/instahelp_activity.dart';
import '../../domain/models/instahelp_mode.dart';
import '../providers/instahelp_vendor_providers.dart';
import '../widgets/duration_form_dialog.dart';
import '../widgets/activity_form_dialog.dart';
import '../widgets/slot_config_section.dart';
import '../widgets/financial_config_section.dart';
import '../widgets/date_override_section.dart';

class VendorInstaHelpPage extends ConsumerStatefulWidget {
  const VendorInstaHelpPage({super.key});

  @override
  ConsumerState<VendorInstaHelpPage> createState() => _VendorInstaHelpPageState();
}

class _VendorInstaHelpPageState extends ConsumerState<VendorInstaHelpPage>
    with SingleTickerProviderStateMixin {
  late final TabController _innerTab;

  @override
  void initState() {
    super.initState();
    _innerTab = TabController(length: 3, vsync: this);
  }

  void _setShellActions() {
    final vendor = ref.read(currentVendorUserProvider);
    if (vendor == null) return;
    final modes = ref.read(vendorModesProvider(vendor.id)).valueOrNull ?? [];
    ref.read(vendorShellActionsProvider.notifier).state = [
      if (modes.isNotEmpty)
        IconButton(
          icon: const Icon(Icons.swap_vert_rounded),
          tooltip: 'Reorder Modes',
          onPressed: () => _openReorder(modes),
        ),
      IconButton(
        icon: const Icon(Icons.refresh_rounded),
        tooltip: 'Refresh',
        onPressed: () => ref.invalidate(vendorModesProvider(vendor.id)),
      ),
    ];
  }

  void _openReorder(List<InstaHelpMode> modes) {
    final vendor = ref.read(currentVendorUserProvider);
    if (vendor == null) return;
    showDialog(
      context: context,
      builder: (ctx) => _ModeReorderDialog(
        modes: modes,
        onSave: (reordered) =>
            ref.read(vendorModesProvider(vendor.id).notifier).reorder(reordered),
      ),
    );
  }

  @override
  void dispose() {
    _innerTab.dispose();
    ref.read(vendorShellActionsProvider.notifier).state = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vendor = ref.watch(currentVendorUserProvider);
    if (vendor == null) {
      return const Center(child: CircularProgressIndicator());
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _setShellActions();
    });

    final modesAsync = ref.watch(vendorModesProvider(vendor.id));

    return ColoredBox(
      color: AppColors.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 16),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.flash_on_rounded, color: AppColors.primary, size: 22),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('InstaHelp',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  Text('On-demand & scheduled services',
                      style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                ],
              ),
            ]),
          ),
          Expanded(
            child: _InstaHelpConfigTab(
              vendorId: vendor.id,
              modesAsync: modesAsync,
              innerTab: _innerTab,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Config tab ────────────────────────────────────────────────────────────────

class _InstaHelpConfigTab extends ConsumerWidget {
  final String vendorId;
  final AsyncValue<List<InstaHelpMode>> modesAsync;
  final TabController innerTab;

  const _InstaHelpConfigTab({
    required this.vendorId,
    required this.modesAsync,
    required this.innerTab,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isEligible =
        ref.watch(vendorInstaHelpEligibilityProvider(vendorId)).valueOrNull ?? true;
    return Column(
      children: [
        // Inner TabBar: Scheduled | Instant | Car Wash
        modesAsync.when(
          loading: () => const SizedBox.shrink(),
          error: (e, s) => const SizedBox.shrink(),
          data: (modes) => modes.isEmpty
              ? const SizedBox.shrink()
              : Material(
                  color: Colors.white,
                  child: TabBar(
                    controller: innerTab,
                    labelColor: AppColors.primary,
                    unselectedLabelColor: AppColors.textSecondary,
                    indicatorColor: AppColors.primary,
                    indicatorWeight: 2.5,
                    dividerColor: AppColors.border,
                    labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    unselectedLabelStyle: const TextStyle(fontSize: 14),
                    tabs: modes.map((m) => Tab(text: m.displayName)).toList(),
                  ),
                ),
        ),
        Expanded(
          child: modesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Text('Failed to load: $e',
                  style: const TextStyle(color: AppColors.error, fontSize: 14)),
            ),
            data: (modes) {
              if (modes.isEmpty) {
                return _EnableInstaHelpCard(vendorId: vendorId);
              }

              return TabBarView(
                controller: innerTab,
                children: modes.map((m) => _ModeTabContent(
                  mode: m,
                  vendorId: vendorId,
                  showSlotConfig: m.modeType == 'scheduled',
                  isEligible: isEligible,
                )).toList(),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ── Enable prompt ─────────────────────────────────────────────────────────────

class _EnableInstaHelpCard extends ConsumerStatefulWidget {
  final String vendorId;
  const _EnableInstaHelpCard({required this.vendorId});

  @override
  ConsumerState<_EnableInstaHelpCard> createState() => _EnableInstaHelpCardState();
}

class _EnableInstaHelpCardState extends ConsumerState<_EnableInstaHelpCard> {
  bool _loading = false;

  Future<void> _enable() async {
    setState(() => _loading = true);
    try {
      await ref.read(vendorModesProvider(widget.vendorId).notifier).initialize();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.flash_on_rounded, size: 48, color: AppColors.primary),
            ),
            const SizedBox(height: 24),
            const Text('InstaHelp Not Set Up',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const SizedBox(height: 10),
            const Text(
              'Enable InstaHelp to offer on-demand and scheduled\nservices directly to customers in your area.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: AppColors.textSecondary, height: 1.5),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: _loading ? null : _enable,
              icon: _loading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.flash_on_rounded, size: 18),
              label: const Text('Enable InstaHelp'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                minimumSize: const Size(0, 48),
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Mode tab content ──────────────────────────────────────────────────────────

class _ModeTabContent extends ConsumerWidget {
  final InstaHelpMode mode;
  final String vendorId;
  final bool showSlotConfig;
  final bool isEligible;
  const _ModeTabContent({required this.mode, required this.vendorId, required this.showSlotConfig, required this.isEligible});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requestsAsync = ref.watch(vendorInstaHelpRequestsProvider(mode.id));
    final allReqs = requestsAsync.valueOrNull ?? [];
    final pending = allReqs.where((r) => r['status'] == 'pending').toList();
    final rejected = allReqs.where((r) => r['status'] == 'rejected').toList();
    final hasSlotPending = pending.any((r) => r['request_type'] == 'instahelp_slot_config');
    final hasFinancialPending = pending.any((r) => r['request_type'] == 'instahelp_financial_config');
    final hasSlotRejected = rejected.any((r) => r['request_type'] == 'instahelp_slot_config');
    final hasFinancialRejected = rejected.any((r) => r['request_type'] == 'instahelp_financial_config');
    final slotRejectedReason = rejected
        .where((r) => r['request_type'] == 'instahelp_slot_config')
        .map((r) => r['rejection_reason'] as String?)
        .firstOrNull;
    final financialRejectedReason = rejected
        .where((r) => r['request_type'] == 'instahelp_financial_config')
        .map((r) => r['rejection_reason'] as String?)
        .firstOrNull;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        if (!isEligible)
          Container(
            margin: const EdgeInsets.only(bottom: 20),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
            ),
            child: const Row(children: [
              Icon(Icons.lock_outline_rounded, color: AppColors.error, size: 18),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'An active InstaHelp subscription is required to add or activate services.',
                  style: TextStyle(fontSize: 13, color: AppColors.error),
                ),
              ),
            ]),
          ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            title: Text('${mode.displayName} Mode Active',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            subtitle: Text(
              mode.isActive ? 'Visible to customers in your area' : 'Hidden from customers',
              style: TextStyle(fontSize: 13, color: mode.isActive ? AppColors.success : AppColors.textSecondary),
            ),
            value: mode.isActive,
            onChanged: (!isEligible && !mode.isActive)
                ? null
                : (v) => ref.read(vendorModesProvider(vendorId).notifier).toggleActive(mode.id, isActive: v),
            activeThumbColor: AppColors.success,
          ),
        ),
        const SizedBox(height: 20),
        if (hasFinancialPending)
          _PendingConfigBanner(label: 'Financial configuration change pending admin approval'),
        if (hasFinancialRejected)
          _RejectedConfigBanner(
            label: 'Financial configuration change was rejected',
            reason: financialRejectedReason,
          ),
        VendorFinancialConfigSection(modeId: mode.id),
        const SizedBox(height: 20),
        _DurationSection(modeId: mode.id, showSlotSchedule: showSlotConfig, isEligible: isEligible),
        if (showSlotConfig) ...[
          const SizedBox(height: 20),
          if (hasSlotPending)
            _PendingConfigBanner(label: 'Slot configuration change pending admin approval'),
          if (hasSlotRejected)
            _RejectedConfigBanner(
              label: 'Slot configuration change was rejected',
              reason: slotRejectedReason,
            ),
          VendorSlotConfigSection(modeId: mode.id),
        ],
        const SizedBox(height: 20),
        _ActivitiesSection(modeId: mode.id, isEligible: isEligible),
        const SizedBox(height: 20),
        VendorDateOverrideSection(modeId: mode.id),
        const SizedBox(height: 24),
      ],
    );
  }
}


// ── Pending config banner ─────────────────────────────────────────────────────

class _PendingConfigBanner extends StatelessWidget {
  final String label;
  const _PendingConfigBanner({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFFCA28)),
      ),
      child: Row(children: [
        const Icon(Icons.pending_outlined, size: 16, color: Color(0xFFF57F17)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(label,
              style: const TextStyle(fontSize: 12, color: Color(0xFF5D4037))),
        ),
      ]),
    );
  }
}

// ── Pending approval row ──────────────────────────────────────────────────────

class _PendingApprovalBadge extends StatelessWidget {
  final String label;
  const _PendingApprovalBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFFF9800)),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 10, color: Color(0xFFE65100), fontWeight: FontWeight.w600),
      ),
    );
  }
}

// ── Rejected config banner ────────────────────────────────────────────────────

class _RejectedConfigBanner extends StatelessWidget {
  final String label;
  final String? reason;
  const _RejectedConfigBanner({required this.label, this.reason});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.35)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.cancel_outlined, size: 16, color: AppColors.error),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: const TextStyle(fontSize: 12, color: AppColors.error, fontWeight: FontWeight.w600)),
            if (reason != null && reason!.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text('Reason: $reason',
                  style: TextStyle(fontSize: 11, color: AppColors.error.withValues(alpha: 0.8))),
            ],
          ]),
        ),
      ]),
    );
  }
}

// ── Rejected badge ────────────────────────────────────────────────────────────

class _RejectedBadge extends StatelessWidget {
  final String label;
  const _RejectedBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, color: AppColors.error, fontWeight: FontWeight.w600),
      ),
    );
  }
}

// ── Rejected request row ──────────────────────────────────────────────────────

class _RejectedRequestRow extends ConsumerWidget {
  final Map<String, dynamic> req;
  const _RejectedRequestRow({required this.req});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = (req['request_data'] as Map<String, dynamic>?) ?? {};
    final type = req['request_type'] as String? ?? '';
    final reason = req['rejection_reason'] as String?;
    final id = req['id'] as String;
    final String title;
    if (type.contains('duration')) {
      final label = data['label'] as String? ?? req['service_name'] as String? ?? '—';
      final minutes = data['duration_minutes'] as int? ?? 0;
      title = '$label · $minutes min';
    } else {
      title = data['title'] as String? ?? req['service_name'] as String? ?? '—';
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(
          padding: EdgeInsets.only(top: 3),
          child: Icon(Icons.cancel_outlined, size: 14, color: AppColors.error),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            if (reason != null && reason.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text('Reason: $reason',
                  style: const TextStyle(fontSize: 11, color: AppColors.error)),
            ],
          ]),
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline_rounded, size: 16, color: AppColors.error),
          tooltip: 'Dismiss',
          visualDensity: VisualDensity.compact,
          onPressed: () async {
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                title: const Text('Remove?', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                content: const Text('This rejected request will be removed from your view.', style: TextStyle(fontSize: 13)),
                actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                actions: [
                  Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(90, 40),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                      ),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.error,
                        minimumSize: const Size(90, 40),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                      ),
                      child: const Text('Remove'),
                    ),
                  ]),
                ],
              ),
            );
            if (confirmed != true) return;
            try {
              await ref.read(instaHelpVendorRepoProvider).dismissRejectedRequest(id);
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed to dismiss: $e'), backgroundColor: AppColors.error),
                );
              }
            }
          },
        ),
      ]),
    );
  }
}

// ── Duration section ──────────────────────────────────────────────────────────

class _DurationSection extends ConsumerStatefulWidget {
  final String modeId;
  final bool showSlotSchedule;
  final bool isEligible;
  const _DurationSection({required this.modeId, required this.showSlotSchedule, required this.isEligible});

  @override
  ConsumerState<_DurationSection> createState() => _DurationSectionState();
}

class _DurationSectionState extends ConsumerState<_DurationSection> {

  static final _currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);

  void _openCreate() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => VendorDurationFormDialog(
        showSlotSchedule: widget.showSlotSchedule,
        onSave: ({
          required label, required durationMinutes, required price,
          required discountType, required discountValue, required isActive,
          required slotStartTime, required slotEndTime,
          required slotIntervalMinutes, required maxBookingsPerSlot,
        }) =>
            ref.read(vendorDurationsProvider(widget.modeId).notifier).create(
              label: label, durationMinutes: durationMinutes, price: price,
              discountType: discountType, discountValue: discountValue, isActive: isActive,
              slotStartTime: slotStartTime, slotEndTime: slotEndTime,
              slotIntervalMinutes: slotIntervalMinutes, maxBookingsPerSlot: maxBookingsPerSlot,
            ),
      ),
    );
  }

  void _openEdit(InstaHelpDuration duration) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => VendorDurationFormDialog(
        existing: duration,
        showSlotSchedule: widget.showSlotSchedule,
        onSave: ({
          required label, required durationMinutes, required price,
          required discountType, required discountValue, required isActive,
          required slotStartTime, required slotEndTime,
          required slotIntervalMinutes, required maxBookingsPerSlot,
        }) =>
            ref.read(vendorDurationsProvider(widget.modeId).notifier).update(duration.id,
              label: label, durationMinutes: durationMinutes, price: price,
              discountType: discountType, discountValue: discountValue, isActive: isActive,
              slotStartTime: slotStartTime, slotEndTime: slotEndTime,
              slotIntervalMinutes: slotIntervalMinutes, maxBookingsPerSlot: maxBookingsPerSlot,
            ),
      ),
    );
  }

  Future<void> _confirmDelete(InstaHelpDuration d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Duration'),
        content: Text('Delete "${d.label}"? This cannot be undone.'),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        actions: [
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            OutlinedButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              style: OutlinedButton.styleFrom(minimumSize: const Size(90, 40), padding: const EdgeInsets.symmetric(horizontal: 16)),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: FilledButton.styleFrom(backgroundColor: AppColors.error, minimumSize: const Size(90, 40), padding: const EdgeInsets.symmetric(horizontal: 16)),
              child: const Text('Delete'),
            ),
          ]),
        ],
      ),
    );
    if (ok == true) {
      try {
        await ref.read(vendorDurationsProvider(widget.modeId).notifier).delete(d.id);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Delete failed: $e'), backgroundColor: AppColors.error),
          );
        }
      }
    }
  }

  Future<void> _onMove(List<InstaHelpDuration> current, int oldIndex, int newIndex) async {
    final reordered = List.of(current);
    final item = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, item);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Save New Order?', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        content: const Text('Apply this new duration order for customers?', style: TextStyle(fontSize: 13)),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        actions: [
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            OutlinedButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              style: OutlinedButton.styleFrom(minimumSize: const Size(90, 40), padding: const EdgeInsets.symmetric(horizontal: 16)),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary, minimumSize: const Size(90, 40), padding: const EdgeInsets.symmetric(horizontal: 16)),
              child: const Text('Save'),
            ),
          ]),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await ref.read(vendorDurationsProvider(widget.modeId).notifier).reorder(reordered);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Reorder failed: $e'), backgroundColor: AppColors.error),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final durationsAsync = ref.watch(vendorDurationsProvider(widget.modeId));
    final requestsAsync = ref.watch(vendorInstaHelpRequestsProvider(widget.modeId));
    final allReqs = requestsAsync.valueOrNull ?? [];
    final pendingReqs = allReqs.where((r) => r['status'] == 'pending').toList();
    final rejectedReqs = allReqs.where((r) => r['status'] == 'rejected').toList();

    // Pending lookup maps
    final pendingByResourceId = <String, String>{};
    final pendingNew = <Map<String, dynamic>>[];
    for (final r in pendingReqs) {
      final type = r['request_type'] as String? ?? '';
      final rid = r['instahelp_resource_id'] as String?;
      if (type == 'instahelp_new_duration') {
        pendingNew.add(r);
      } else if (rid != null &&
          (type == 'instahelp_edit_duration' || type == 'instahelp_delete_duration')) {
        pendingByResourceId[rid] = type;
      }
    }

    // Rejected lookup maps
    final rejectedByResourceId = <String, Map<String, dynamic>>{};
    final rejectedNew = <Map<String, dynamic>>[];
    for (final r in rejectedReqs) {
      final type = r['request_type'] as String? ?? '';
      final rid = r['instahelp_resource_id'] as String?;
      if (type == 'instahelp_new_duration') {
        rejectedNew.add(r);
      } else if (rid != null &&
          (type == 'instahelp_edit_duration' || type == 'instahelp_delete_duration')) {
        rejectedByResourceId[rid] = r;
      }
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
            child: Row(children: [
              const Icon(Icons.timer_rounded, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              const Text('Duration & Pricing',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              const Spacer(),
              FilledButton.icon(
                onPressed: widget.isEligible ? _openCreate : null,
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Add Duration'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  minimumSize: const Size(0, 40),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  textStyle: const TextStyle(fontSize: 13),
                ),
              ),
            ]),
          ),
          const Divider(height: 1),
          durationsAsync.when(
            loading: () => const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Error: $e', style: const TextStyle(color: AppColors.error)),
            ),
            data: (durations) {
              if (durations.isEmpty && pendingNew.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 36),
                  child: Center(
                    child: Column(children: [
                      const Icon(Icons.timer_off_rounded, size: 36, color: AppColors.textSecondary),
                      const SizedBox(height: 8),
                      const Text('No duration options yet', style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
                      const SizedBox(height: 4),
                      const Text('Add your first duration option above',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    ]),
                  ),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (durations.isNotEmpty) ...[
                    // Header row
                    Container(
                      color: AppColors.background,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: const Row(children: [
                        SizedBox(width: 110, child: Text('POSITION', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary), textAlign: TextAlign.center)),
                        SizedBox(width: 160, child: Text('DURATION', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                        SizedBox(width: 80, child: Text('PRICE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                        SizedBox(width: 80, child: Text('DISCOUNT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                        SizedBox(width: 80, child: Text('FINAL', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                        SizedBox(width: 110, child: Text('STATUS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                        Text('ACTIONS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                      ]),
                    ),
                    const Divider(height: 1),
                    Column(
                      children: durations.asMap().entries.map((entry) {
                        final idx = entry.key;
                        final d = entry.value;
                        final pendingType = pendingByResourceId[d.id];
                        final hasPending = pendingType != null;
                        final isDeletePending = pendingType == 'instahelp_delete_duration';
                        final rejectedReq = rejectedByResourceId[d.id];
                        final hasRejected = rejectedReq != null && !hasPending;
                        return Container(
                          decoration: const BoxDecoration(
                            border: Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          child: Row(children: [
                            SizedBox(
                              width: 110,
                              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                _ArrowBtn(
                                  icon: Icons.keyboard_arrow_up_rounded,
                                  tooltip: 'Move up',
                                  enabled: idx > 0,
                                  onTap: () => _onMove(durations, idx, idx - 1),
                                ),
                                const SizedBox(width: 4),
                                Tooltip(
                                  message: 'Jump to position',
                                  child: PopupMenuButton<int>(
                                    tooltip: '',
                                    offset: const Offset(0, 28),
                                    onSelected: (target) => _onMove(durations, idx, target),
                                    itemBuilder: (_) => [
                                      for (int p = 0; p < durations.length; p++)
                                        if (p != idx)
                                          PopupMenuItem<int>(
                                            value: p,
                                            height: 36,
                                            child: Text('Position ${p + 1}',
                                                style: const TextStyle(fontSize: 13)),
                                          ),
                                    ],
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: AppColors.primary.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
                                      ),
                                      child: Text(
                                        '${idx + 1}',
                                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.primary),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                _ArrowBtn(
                                  icon: Icons.keyboard_arrow_down_rounded,
                                  tooltip: 'Move down',
                                  enabled: idx < durations.length - 1,
                                  onTap: () => _onMove(durations, idx, idx + 1),
                                ),
                              ]),
                            ),
                            SizedBox(width: 160, child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(d.label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                Text('${d.durationMinutes} min', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                              ],
                            )),
                            SizedBox(width: 80, child: Text(_currency.format(d.price), style: const TextStyle(fontSize: 13))),
                            SizedBox(width: 80, child: _DiscountBadge(d: d)),
                            SizedBox(width: 80, child: Text(_currency.format(d.finalPrice),
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.success))),
                            SizedBox(width: 110, child: hasPending
                                ? _PendingApprovalBadge(label: isDeletePending ? 'Delete Pending' : 'Edit Pending')
                                : hasRejected
                                    ? _RejectedBadge(label: rejectedReq['request_type'] == 'instahelp_delete_duration' ? 'Delete Rejected' : 'Edit Rejected')
                                    : Switch(
                                        value: d.isActive,
                                        onChanged: (v) async {
                                          final messenger = ScaffoldMessenger.of(context);
                                          try {
                                            await ref.read(vendorDurationsProvider(widget.modeId).notifier).toggleActive(d.id, isActive: v);
                                          } catch (e) {
                                            messenger.showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.error));
                                          }
                                        },
                                        activeTrackColor: AppColors.success,
                                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      )),
                            if (!hasPending && !hasRejected)
                              Row(mainAxisSize: MainAxisSize.min, children: [
                                IconButton(
                                  icon: const Icon(Icons.edit_rounded, size: 17, color: AppColors.primary),
                                  tooltip: 'Edit',
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () => _openEdit(d),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline_rounded, size: 17, color: AppColors.error),
                                  tooltip: 'Delete',
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () => _confirmDelete(d),
                                ),
                              ]),
                          ]),
                        );
                      }).toList(),
                    ),
                  ],
                  if (pendingNew.isNotEmpty) ...[
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                      child: Row(children: [
                        const Icon(Icons.pending_outlined, size: 14, color: Color(0xFFF57F17)),
                        const SizedBox(width: 6),
                        Text('${pendingNew.length} new duration${pendingNew.length > 1 ? 's' : ''} pending admin approval',
                            style: const TextStyle(fontSize: 12, color: Color(0xFF5D4037), fontWeight: FontWeight.w500)),
                      ]),
                    ),
                    for (final req in pendingNew)
                      _PendingDurationRow(req: req, currency: _currency),
                    const SizedBox(height: 8),
                  ],
                  if (rejectedNew.isNotEmpty) ...[
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                      child: Row(children: [
                        const Icon(Icons.cancel_outlined, size: 14, color: AppColors.error),
                        const SizedBox(width: 6),
                        Text('${rejectedNew.length} new duration${rejectedNew.length > 1 ? 's' : ''} rejected',
                            style: const TextStyle(fontSize: 12, color: AppColors.error, fontWeight: FontWeight.w500)),
                      ]),
                    ),
                    for (final req in rejectedNew)
                      _RejectedRequestRow(req: req),
                    const SizedBox(height: 8),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _PendingDurationRow extends StatelessWidget {
  final Map<String, dynamic> req;
  final NumberFormat currency;
  const _PendingDurationRow({required this.req, required this.currency});

  @override
  Widget build(BuildContext context) {
    final data = (req['request_data'] as Map<String, dynamic>?) ?? {};
    final label = data['label'] as String? ?? req['service_name'] as String? ?? '—';
    final minutes = data['duration_minutes'] as int? ?? 0;
    final price = (data['price'] as num?)?.toDouble() ?? 0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(children: [
        Container(
          width: 6, height: 6,
          decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFFF9800)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            Text('$minutes min · ${currency.format(price)}',
                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
          ]),
        ),
        const _PendingApprovalBadge(label: 'Pending Review'),
      ]),
    );
  }
}

class _DiscountBadge extends StatelessWidget {
  final InstaHelpDuration d;
  const _DiscountBadge({required this.d});

  @override
  Widget build(BuildContext context) {
    if (!d.hasDiscount) return const Text('None', style: TextStyle(color: AppColors.textSecondary, fontSize: 12));
    final label = d.discountType == 'percentage'
        ? '${d.discountValue.toStringAsFixed(0)}% off'
        : '₹${d.discountValue.toStringAsFixed(0)} off';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Text(label, style: const TextStyle(fontSize: 11, color: AppColors.error, fontWeight: FontWeight.w600)),
    );
  }
}

// ── Activities section ────────────────────────────────────────────────────────

class _ActivitiesSection extends ConsumerWidget {
  final String modeId;
  final bool isEligible;
  const _ActivitiesSection({required this.modeId, required this.isEligible});

  void _openCreate(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => VendorActivityFormDialog(
        onSave: ({required title, required includedItems, required excludedItems, required isActive}) =>
            ref.read(vendorActivitiesProvider(modeId).notifier).create(
              title: title, includedItems: includedItems, excludedItems: excludedItems, isActive: isActive,
            ),
      ),
    );
  }

  void _openEdit(BuildContext context, WidgetRef ref, InstaHelpActivity activity) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => VendorActivityFormDialog(
        existing: activity,
        onSave: ({required title, required includedItems, required excludedItems, required isActive}) =>
            ref.read(vendorActivitiesProvider(modeId).notifier).update(activity.id,
              title: title, includedItems: includedItems, excludedItems: excludedItems, isActive: isActive,
            ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, InstaHelpActivity a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Activity'),
        content: Text('Delete "${a.title}"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        await ref.read(vendorActivitiesProvider(modeId).notifier).delete(a.id);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Delete failed: $e'), backgroundColor: AppColors.error),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activitiesAsync = ref.watch(vendorActivitiesProvider(modeId));
    final requestsAsync = ref.watch(vendorInstaHelpRequestsProvider(modeId));
    final allReqs = requestsAsync.valueOrNull ?? [];
    final pendingReqs = allReqs.where((r) => r['status'] == 'pending').toList();
    final rejectedReqs = allReqs.where((r) => r['status'] == 'rejected').toList();

    final pendingByResourceId = <String, String>{};
    final pendingNew = <Map<String, dynamic>>[];
    for (final r in pendingReqs) {
      final type = r['request_type'] as String? ?? '';
      final rid = r['instahelp_resource_id'] as String?;
      if (type == 'instahelp_new_activity') {
        pendingNew.add(r);
      } else if (rid != null &&
          (type == 'instahelp_edit_activity' || type == 'instahelp_delete_activity')) {
        pendingByResourceId[rid] = type;
      }
    }

    final rejectedByResourceId = <String, Map<String, dynamic>>{};
    final rejectedNew = <Map<String, dynamic>>[];
    for (final r in rejectedReqs) {
      final type = r['request_type'] as String? ?? '';
      final rid = r['instahelp_resource_id'] as String?;
      if (type == 'instahelp_new_activity') {
        rejectedNew.add(r);
      } else if (rid != null &&
          (type == 'instahelp_edit_activity' || type == 'instahelp_delete_activity')) {
        rejectedByResourceId[rid] = r;
      }
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
            child: Row(children: [
              const Icon(Icons.layers_rounded, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              const Text('Activity Groups',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              const Spacer(),
              FilledButton.icon(
                onPressed: isEligible ? () => _openCreate(context, ref) : null,
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Add Group'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  minimumSize: const Size(0, 40),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  textStyle: const TextStyle(fontSize: 13),
                ),
              ),
            ]),
          ),
          const Divider(height: 1),
          activitiesAsync.when(
            loading: () => const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Error: $e', style: const TextStyle(color: AppColors.error)),
            ),
            data: (activities) {
              if (activities.isEmpty && pendingNew.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 36),
                  child: Center(child: Text('No activity groups yet',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 14))),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (activities.isNotEmpty)
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: activities.length,
                      separatorBuilder: (_, i) => const Divider(height: 1, color: AppColors.border),
                      itemBuilder: (_, i) {
                        final a = activities[i];
                        final pendingType = pendingByResourceId[a.id];
                        final hasPending = pendingType != null;
                        final isDeletePending = pendingType == 'instahelp_delete_activity';
                        final rejectedReq = rejectedByResourceId[a.id];
                        final hasRejected = rejectedReq != null && !hasPending;
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 3),
                                child: Container(
                                  width: 8, height: 8,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: a.isActive ? AppColors.primary : AppColors.textSecondary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(a.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                                    if (hasPending) ...[
                                      const SizedBox(height: 4),
                                      _PendingApprovalBadge(label: isDeletePending ? 'Delete Pending' : 'Edit Pending'),
                                    ] else if (hasRejected) ...[
                                      const SizedBox(height: 4),
                                      _RejectedBadge(label: rejectedReq['request_type'] == 'instahelp_delete_activity' ? 'Delete Rejected' : 'Edit Rejected'),
                                      if ((rejectedReq['rejection_reason'] as String?)?.isNotEmpty == true) ...[
                                        const SizedBox(height: 2),
                                        Text(rejectedReq['rejection_reason'] as String,
                                            style: const TextStyle(fontSize: 11, color: AppColors.error)),
                                      ],
                                    ] else ...[
                                      if (a.includedItems.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Text('Included: ${a.includedItems.join(', ')}',
                                            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                                      ],
                                      if (a.excludedItems.isNotEmpty)
                                        Text('Excluded: ${a.excludedItems.join(', ')}',
                                            style: const TextStyle(fontSize: 12, color: AppColors.error)),
                                    ],
                                  ],
                                ),
                              ),
                              if (!hasPending && !hasRejected) ...[
                                Switch(
                                  value: a.isActive,
                                  onChanged: (v) async {
                                    try {
                                      await ref.read(vendorActivitiesProvider(modeId).notifier).toggleActive(a.id, isActive: v);
                                    } catch (e) {
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text('$e'), backgroundColor: AppColors.error),
                                        );
                                      }
                                    }
                                  },
                                  activeTrackColor: AppColors.success,
                                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                IconButton(
                                  icon: const Icon(Icons.edit_rounded, size: 17, color: AppColors.primary),
                                  tooltip: 'Edit',
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () => _openEdit(context, ref, a),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline_rounded, size: 17, color: AppColors.error),
                                  tooltip: 'Delete',
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () => _confirmDelete(context, ref, a),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                  if (pendingNew.isNotEmpty) ...[
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                      child: Row(children: [
                        const Icon(Icons.pending_outlined, size: 14, color: Color(0xFFF57F17)),
                        const SizedBox(width: 6),
                        Text('${pendingNew.length} new activity group${pendingNew.length > 1 ? 's' : ''} pending admin approval',
                            style: const TextStyle(fontSize: 12, color: Color(0xFF5D4037), fontWeight: FontWeight.w500)),
                      ]),
                    ),
                    for (final req in pendingNew)
                      _PendingActivityRow(req: req),
                    const SizedBox(height: 8),
                  ],
                  if (rejectedNew.isNotEmpty) ...[
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                      child: Row(children: [
                        const Icon(Icons.cancel_outlined, size: 14, color: AppColors.error),
                        const SizedBox(width: 6),
                        Text('${rejectedNew.length} new activity group${rejectedNew.length > 1 ? 's' : ''} rejected',
                            style: const TextStyle(fontSize: 12, color: AppColors.error, fontWeight: FontWeight.w500)),
                      ]),
                    ),
                    for (final req in rejectedNew)
                      _RejectedRequestRow(req: req),
                    const SizedBox(height: 8),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _PendingActivityRow extends StatelessWidget {
  final Map<String, dynamic> req;
  const _PendingActivityRow({required this.req});

  @override
  Widget build(BuildContext context) {
    final data = (req['request_data'] as Map<String, dynamic>?) ?? {};
    final title = data['title'] as String? ?? req['service_name'] as String? ?? '—';
    final included = (data['included_items'] as List?)?.cast<String>() ?? [];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(children: [
        const Padding(
          padding: EdgeInsets.only(top: 2),
          child: Icon(Icons.pending_outlined, size: 14, color: Color(0xFFFF9800)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            if (included.isNotEmpty)
              Text('Included: ${included.join(', ')}',
                  style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
          ]),
        ),
        const _PendingApprovalBadge(label: 'Pending Review'),
      ]),
    );
  }
}

// ── Mode reorder dialog ───────────────────────────────────────────────────────

class _ModeReorderDialog extends StatefulWidget {
  final List<InstaHelpMode> modes;
  final Future<void> Function(List<InstaHelpMode>) onSave;
  const _ModeReorderDialog({required this.modes, required this.onSave});

  @override
  State<_ModeReorderDialog> createState() => _ModeReorderDialogState();
}

class _ModeReorderDialogState extends State<_ModeReorderDialog> {
  late List<InstaHelpMode> _ordered;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ordered = List.of(widget.modes);
  }

  Future<void> _save() async {
    setState(() { _saving = true; _error = null; });
    try {
      await widget.onSave(_ordered);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Reorder Modes', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Drag to change the order customers see these modes.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: _ordered.length * 60.0,
              child: ReorderableListView(
                shrinkWrap: true,
                onReorder: (oldIndex, newIndex) {
                  setState(() {
                    if (newIndex > oldIndex) newIndex--;
                    final item = _ordered.removeAt(oldIndex);
                    _ordered.insert(newIndex, item);
                  });
                },
                children: [
                  for (final mode in _ordered)
                    ListTile(
                      key: ValueKey(mode.id),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      leading: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(_modeIcon(mode.modeType), size: 18, color: AppColors.primary),
                      ),
                      title: Text(mode.displayName,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      subtitle: Text(mode.isActive ? 'Active' : 'Inactive',
                          style: TextStyle(fontSize: 11,
                              color: mode.isActive ? AppColors.success : AppColors.textSecondary)),
                      trailing: const Icon(Icons.drag_handle_rounded, color: AppColors.textSecondary),
                    ),
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 12)),
            ],
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      actions: [
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          OutlinedButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(90, 40),
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              minimumSize: const Size(90, 40),
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            child: _saving
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text('Save Order'),
          ),
        ]),
      ],
    );
  }

  IconData _modeIcon(String type) {
    switch (type) {
      case 'scheduled': return Icons.schedule_rounded;
      case 'instant':   return Icons.flash_on_rounded;
      case 'car_wash':  return Icons.local_car_wash_rounded;
      default:          return Icons.miscellaneous_services_rounded;
    }
  }
}

// ── Arrow button for position controls ───────────────────────────────────────

class _ArrowBtn extends StatelessWidget {
  const _ArrowBtn({
    required this.icon,
    required this.tooltip,
    required this.enabled,
    required this.onTap,
  });
  final IconData icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Icon(
            icon,
            size: 18,
            color: enabled ? AppColors.textSecondary : AppColors.border,
          ),
        ),
      ),
    );
  }
}
