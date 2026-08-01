import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../models/amc_contract_model.dart';
import '../providers/amc_contract_provider.dart';
import '../providers/amc_provider.dart';
import '../widgets/amc_bottom_sheet.dart';
import '../../bookings/services/bookings_providers.dart';
import '../../cart/models/cart_item.dart';
import '../../cart/providers/cart_provider.dart';
import '../../cart/services/checkout_service.dart';
import '../../cart/utils/cart_launcher.dart';

class AmcContractDetailsScreen extends ConsumerStatefulWidget {
  final String contractId;
  final String initialPlanName;

  const AmcContractDetailsScreen({
    super.key,
    required this.contractId,
    this.initialPlanName = 'AMC Contract',
  });

  @override
  ConsumerState<AmcContractDetailsScreen> createState() =>
      _AmcContractDetailsScreenState();
}

class _AmcContractDetailsScreenState
    extends ConsumerState<AmcContractDetailsScreen> {
  bool _cancelling = false;
  bool _requesting = false;
  bool _cancellingRequest = false;
  bool _renewing = false;
  bool _hasPendingRequest = false;
  String? _pendingRequestId;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) {
        ref.invalidate(amcContractProvider(widget.contractId));
        _loadPendingRequestStatus();
      }
    });
  }

  Future<void> _loadPendingRequestStatus() async {
    try {
      final id =
          await CheckoutService().getActivePendingRequest(widget.contractId);
      if (mounted) {
        setState(() {
          _hasPendingRequest = id != null;
          _pendingRequestId = id;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final contractAsync = ref.watch(amcContractProvider(widget.contractId));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('AMC Contract'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: contractAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error loading contract: $e')),
        data: (contract) {
          if (contract == null) {
            return const Center(child: Text('Contract not found.'));
          }
          return _ContractContent(contract: contract);
        },
      ),
      bottomNavigationBar: contractAsync.maybeWhen(
        data: (contract) {
          if (contract == null) return null;
          if (contract.status == 'cancelled') {
            return _MembershipCancelledBar(
              reason: contract.cancellationReason,
            );
          }
          if (contract.isCancellationRequested) {
            return _CancellationPendingBar(
              reason: contract.cancellationReason,
            );
          }
          if (contract.isRenewable) {
            return _MembershipCompletedBar(
              renewing: _renewing,
              onRenew: () => _startRenewalFlow(contract),
            );
          }
          if (contract.status != 'active') return null;
          return _ActionBar(
            cancelling: _cancelling,
            requesting: _requesting,
            cancellingRequest: _cancellingRequest,
            hasPendingRequest: _hasPendingRequest,
            onRequest: _hasPendingRequest
                ? null
                : () => _showRequestDialog(context),
            onCancelRequest: _pendingRequestId != null
                ? () => _confirmCancelRequest(context)
                : null,
            onCancel: () => _showCancelChoiceDialog(contract),
          );
        },
        orElse: () => null,
      ),
    );
  }

  Future<void> _showRequestDialog(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final now = DateTime.now();
    final maxDate = now.add(const Duration(days: 4));
    DateTime? selectedDate;
    final notesCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          title: const Text('Request Next Visit'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Choose a preferred date within the next 4 days.',
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: selectedDate ?? now,
                    firstDate: now,
                    lastDate: maxDate,
                    builder: (c, child) => Theme(
                      data: Theme.of(c).copyWith(
                        colorScheme: Theme.of(c).colorScheme.copyWith(
                              primary: AppColors.primary,
                            ),
                      ),
                      child: child!,
                    ),
                  );
                  if (picked != null) {
                    setDialogState(() => selectedDate = picked);
                  }
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    border: Border.all(
                        color: selectedDate != null
                            ? AppColors.primary
                            : AppColors.border),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.calendar_today_rounded,
                        size: 15,
                        color: selectedDate != null
                            ? AppColors.primary
                            : AppColors.textHint,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        selectedDate != null
                            ? _fmtDate(selectedDate!)
                            : 'Select preferred date',
                        style: TextStyle(
                          fontSize: 14,
                          color: selectedDate != null
                              ? AppColors.textPrimary
                              : AppColors.textHint,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notesCtrl,
                maxLines: 3,
                maxLength: 200,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Any notes for the admin? (optional)',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  counterText: '',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: selectedDate == null
                  ? null
                  : () => Navigator.of(ctx).pop(true),
              child: const Text('Submit Request'),
            ),
          ],
        ),
      ),
    );

    final date = selectedDate;
    final notes = notesCtrl.text;
    notesCtrl.dispose();

    if (confirmed != true || date == null || !mounted) return;

    setState(() => _requesting = true);
    try {
      final result = await CheckoutService().requestNextVisit(
        widget.contractId,
        preferredDate: date,
        notes: notes.trim().isEmpty ? null : notes.trim(),
      );
      if (!mounted) return;
      if (result == 'requested') {
        await _loadPendingRequestStatus();
        if (!mounted) return;
        messenger.showSnackBar(
          const SnackBar(
              content: Text(
                  'Request submitted. Admin will contact you to confirm.')),
        );
      } else {
        messenger.showSnackBar(
          const SnackBar(
              content: Text('A scheduling request is already pending.')),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(
          content: Text('Failed to submit request: $e'),
          backgroundColor: AppColors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  static String _fmtDate(DateTime d) {
    const m = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${d.day} ${m[d.month - 1]} ${d.year}';
  }

  Future<void> _confirmCancelRequest(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final requestId = _pendingRequestId;
    if (requestId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Cancel Request'),
        content: const Text(
          'Cancel your scheduling request?\n\n'
          'You can submit a new request at any time.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep Request'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style:
                FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Cancel Request'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _cancellingRequest = true);
    try {
      await CheckoutService().cancelPendingRequest(requestId);
      if (mounted) {
        setState(() {
          _hasPendingRequest = false;
          _pendingRequestId = null;
        });
        messenger.showSnackBar(
          const SnackBar(content: Text('Request cancelled.')),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Failed to cancel request: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _cancellingRequest = false);
    }
  }

  // ── Step 1: ask what to cancel ────────────────────────────────────────────

  Future<void> _showCancelChoiceDialog(AmcContractModel contract) async {
    final nextVisit = contract.visits
        .where((v) => v.status != 'completed' && v.status != 'cancelled')
        .firstOrNull;

    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('What would you like to cancel?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _CancelOptionTile(
              icon: Icons.event_busy_rounded,
              color: const Color(0xFF3182CE),
              title: 'Cancel This Visit',
              subtitle: nextVisit == null
                  ? 'No upcoming visit to cancel'
                  : nextVisit.serviceDate != null
                      ? 'Cancel Visit #${nextVisit.visitNumber ?? '?'} '
                        '(${_fmtDate(nextVisit.serviceDate!)}). '
                        'Your membership remains active.'
                      : 'Cancel Visit #${nextVisit.visitNumber ?? '?'} '
                        '(not yet scheduled). '
                        'Your membership remains active.',
              enabled: nextVisit != null,
              onTap: () => Navigator.of(ctx).pop('visit'),
            ),
            const SizedBox(height: 8),
            _CancelOptionTile(
              icon: Icons.cancel_outlined,
              color: AppColors.error,
              title: 'Cancel Entire AMC Membership',
              subtitle: 'Submit a request to cancel your full membership. '
                  'All remaining visits will be cancelled upon admin approval.',
              enabled: true,
              onTap: () => Navigator.of(ctx).pop('membership'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Go Back'),
          ),
        ],
      ),
    );

    if (choice == null || !mounted) return;

    if (choice == 'visit') {
      await _showVisitCancellationDialog(contract, nextVisit!);
    } else {
      await _showMembershipCancellationDialog(contract);
    }
  }

  // ── Step 2a: confirm visit cancellation ────────────────────────────────────

  Future<void> _showVisitCancellationDialog(
      AmcContractModel contract, AmcVisitModel visit) async {
    final messenger = ScaffoldMessenger.of(context);

    final visitLabel = visit.serviceDate != null
        ? 'Visit #${visit.visitNumber ?? '?'} scheduled for ${_fmtDate(visit.serviceDate!)}'
        : 'Visit #${visit.visitNumber ?? '?'} (awaiting scheduling)';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Cancel This Visit'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              visitLabel,
              style: Theme.of(dlgCtx)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Text(
              'Your cancellation request will be sent to our team for review. '
              'Your AMC membership and all other visits remain unaffected.',
              style: Theme.of(dlgCtx)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dlgCtx).pop(false),
            child: const Text('Go Back'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dlgCtx).pop(true),
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF3182CE)),
            child: const Text('Submit Request'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _cancelling = true);
    try {
      await CheckoutService()
          .requestVisitCancellation(contract.id, visit.id);
      ref.invalidate(amcContractProvider(contract.id));
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Visit cancellation request submitted. '
              'Admin will review and confirm.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(
          content: Text('Failed to submit request: $e'),
          backgroundColor: AppColors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  // ── Step 2b: membership cancellation reason ────────────────────────────────

  Future<void> _showMembershipCancellationDialog(
      AmcContractModel contract) async {
    final messenger = ScaffoldMessenger.of(context);
    const reasons = [
      'Relocating',
      'Service No Longer Required',
      'Cost Issue',
      'Unsatisfied with Service',
      'Other',
    ];
    String? selectedReason;
    final remarksCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          title: const Text('Cancel Entire Membership'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your cancellation request will be sent to our team for review. '
                'Your membership remains active until approved.',
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(
                  labelText: 'Reason for cancellation *',
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                hint: const Text('Select a reason'),
                items: reasons
                    .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                    .toList(),
                onChanged: (v) =>
                    setDialogState(() => selectedReason = v),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: remarksCtrl,
                maxLines: 3,
                maxLength: 300,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Additional remarks (optional)',
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  counterText: '',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Keep Membership'),
            ),
            FilledButton(
              onPressed: selectedReason == null
                  ? null
                  : () => Navigator.of(ctx).pop(true),
              style:
                  FilledButton.styleFrom(backgroundColor: AppColors.error),
              child: const Text('Submit Request'),
            ),
          ],
        ),
      ),
    );

    final reason = selectedReason;
    final remarks = remarksCtrl.text;
    remarksCtrl.dispose();

    if (confirmed != true || reason == null || !mounted) return;

    setState(() => _cancelling = true);
    try {
      await CheckoutService().requestMembershipCancellation(
        contract.id,
        reason: reason,
        remarks: remarks.trim().isEmpty ? null : remarks.trim(),
      );
      ref.invalidate(amcContractProvider(contract.id));
      ref.invalidate(processedBookingsProvider);
      ref.invalidate(myBookingsProvider);
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Cancellation request submitted. '
              'Your membership remains active until our team reviews it.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Failed to submit request: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  // ── AMC Renewal ─────────────────────────────────────────────────────────────

  Future<void> _startRenewalFlow(AmcContractModel contract) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _renewing = true);
    try {
      List<AmcPlanModel> plans;
      try {
        plans = await ref.read(amcPlansProvider(contract.serviceId).future);
      } catch (_) {
        plans = [];
      }
      if (!mounted) return;
      if (plans.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('No AMC plans available for this service.'),
          ),
        );
        return;
      }

      final selection = await showAmcPlansSheet(
        context,
        plans,
        null,
      );
      if (selection == null || !mounted) return;

      final cartItem = CartItem(
        serviceId: contract.serviceId,
        serviceName: contract.serviceName,
        unitPrice: selection.plan.finalPrice,
        quantity: 1,
        isAmc: true,
        amcPlanName: selection.plan.planName,
        amcRecurrenceInterval: selection.plan.serviceIntervalLabel,
        amcPlanId: selection.plan.id,
        amcPricePerVisit: selection.plan.pricePerVisit,
        amcNumVisits: selection.plan.numVisits,
        amcOriginalTotal: selection.plan.originalTotal,
        amcDiscountType: selection.plan.discountType,
        amcDiscountValue: selection.plan.discountValue,
        amcDiscountAmount: selection.plan.discountAmount,
        amcFinalPrice: selection.plan.finalPrice,
        amcPackageDuration: selection.plan.packageDuration,
        amcServiceInterval: selection.plan.serviceInterval,
        amcQuantity: 1,
        amcIsRenewal: true,
        amcPreviousContractId: contract.id,
      );
      ref.read(cartProvider.notifier).replaceWithSingleItem(cartItem);
      if (!mounted) return;
      openCart(context);
    } finally {
      if (mounted) setState(() => _renewing = false);
    }
  }
}

class _ActionBar extends StatelessWidget {
  final bool cancelling;
  final bool requesting;
  final bool cancellingRequest;
  final bool hasPendingRequest;
  final VoidCallback? onRequest;
  final VoidCallback? onCancelRequest;
  final VoidCallback onCancel;

  const _ActionBar({
    required this.cancelling,
    required this.requesting,
    required this.cancellingRequest,
    required this.hasPendingRequest,
    required this.onRequest,
    required this.onCancelRequest,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: cancelling ? null : onCancel,
                icon: cancelling
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 1.5),
                      )
                    : const Icon(Icons.cancel_outlined, size: 16),
                label: const Text('Cancel Membership'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.error,
                  side: const BorderSide(color: AppColors.error),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: hasPendingRequest
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _PendingBadge(),
                        const SizedBox(height: 6),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: cancellingRequest
                                ? null
                                : onCancelRequest,
                            icon: cancellingRequest
                                ? const SizedBox(
                                    width: 13,
                                    height: 13,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 1.5),
                                  )
                                : const Icon(Icons.close_rounded,
                                    size: 14),
                            label: const Text('Cancel Request'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.error,
                              side:
                                  const BorderSide(color: AppColors.error),
                              padding: const EdgeInsets.symmetric(
                                  vertical: 10),
                              textStyle:
                                  const TextStyle(fontSize: 13),
                            ),
                          ),
                        ),
                      ],
                    )
                  : FilledButton.icon(
                      onPressed: requesting ? null : onRequest,
                      icon: requesting
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 1.5, color: Colors.white),
                            )
                          : const Icon(Icons.schedule_send_rounded,
                              size: 16),
                      label: const Text('Request Next Visit'),
                      style: FilledButton.styleFrom(
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PendingBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.warning.withAlpha(20),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.warning.withAlpha(80)),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.hourglass_top_rounded,
              size: 16, color: AppColors.warning),
          SizedBox(width: 6),
          Text(
            'Request Pending',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.warning),
          ),
        ],
      ),
    );
  }
}

// ── Cancel option tile (used inside the choice dialog) ────────────────────────

class _CancelOptionTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback onTap;

  const _CancelOptionTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final effectiveColor = enabled ? color : AppColors.textHint;

    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: effectiveColor.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: effectiveColor.withValues(alpha: 0.25)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(icon, size: 18, color: effectiveColor),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: tt.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: enabled
                          ? AppColors.textPrimary
                          : AppColors.textHint,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: tt.bodySmall?.copyWith(
                        color: enabled
                            ? AppColors.textSecondary
                            : AppColors.textHint),
                  ),
                ],
              ),
            ),
            if (enabled)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(Icons.chevron_right_rounded,
                    size: 18, color: effectiveColor),
              ),
          ],
        ),
      ),
    );
  }
}

class _MembershipCancelledBar extends StatelessWidget {
  final String? reason;
  const _MembershipCancelledBar({this.reason});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.error.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 1),
                child: Icon(Icons.cancel_rounded,
                    size: 18, color: AppColors.error),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Membership Cancelled',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.error,
                      ),
                    ),
                    if (reason != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Reason: $reason',
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.error),
                      ),
                    ],
                    const SizedBox(height: 2),
                    const Text(
                      'This AMC membership has been cancelled. '
                      'No further visits can be requested.',
                      style: TextStyle(
                          fontSize: 11, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CancellationPendingBar extends StatelessWidget {
  final String? reason;
  const _CancellationPendingBar({this.reason});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF3E0),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: const Color(0xFFC05621).withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              const Icon(Icons.hourglass_top_rounded,
                  size: 18, color: Color(0xFFC05621)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Cancellation Request Pending Approval',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFC05621),
                      ),
                    ),
                    if (reason != null)
                      Text(
                        'Reason: $reason',
                        style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF744210)),
                      ),
                    const Text(
                      'Your membership remains active until approved.',
                      style: TextStyle(
                          fontSize: 11, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MembershipCompletedBar extends StatelessWidget {
  final bool renewing;
  final VoidCallback onRenew;

  const _MembershipCompletedBar({
    required this.renewing,
    required this.onRenew,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: AppColors.success.withValues(alpha: 0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.check_circle_rounded,
                      size: 16, color: AppColors.success),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'All visits completed — renew to continue coverage.',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.success),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: renewing ? null : onRenew,
                icon: renewing
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 1.5, color: Colors.white),
                      )
                    : const Icon(Icons.autorenew_rounded, size: 18),
                label: const Text('Renew Membership'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Main content ──────────────────────────────────────────────────────────────

class _ContractContent extends StatelessWidget {
  final AmcContractModel contract;

  const _ContractContent({required this.contract});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SummaryCard(contract: contract),
          if (contract.isRenewal && contract.previousContractId != null) ...[
            const SizedBox(height: 12),
            _PreviousContractCard(previousContractId: contract.previousContractId!),
          ],
          const SizedBox(height: 12),
          _VisitsProgress(contract: contract),
          const SizedBox(height: 12),
          _VisitsList(contract: contract),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ── Previous contract link card ───────────────────────────────────────────────

class _PreviousContractCard extends StatelessWidget {
  final String previousContractId;
  const _PreviousContractCard({required this.previousContractId});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => AmcContractDetailsScreen(
              contractId: previousContractId,
              initialPlanName: 'Previous Contract',
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.history_rounded,
                    size: 18, color: AppColors.primary),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Renewed From',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                    Text(
                      'Tap to view the previous AMC contract',
                      style: TextStyle(
                          fontSize: 11, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  size: 18, color: AppColors.textHint),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Summary card (plan name + status + pricing) ───────────────────────────────

class _SummaryCard extends StatelessWidget {
  final AmcContractModel contract;

  const _SummaryCard({required this.contract});

  @override
  Widget build(BuildContext context) {
    debugPrint('[AMC][Customer][SummaryCard] planName=${contract.planName}  recurrenceInterval=${contract.recurrenceInterval}');
    debugPrint('[AMC][Customer][SummaryCard] originalTotal=${contract.originalTotal}  discountAmount=${contract.discountAmount}  finalPrice=${contract.finalPrice}');
    debugPrint('[AMC][Customer][SummaryCard] effectiveTotalVisits=${contract.effectiveTotalVisits}  completedVisits=${contract.completedVisits}  remainingVisits=${contract.remainingVisits}');
    final tt = Theme.of(context).textTheme;
    final (statusLabel, statusColor, statusBg) = _statusMeta(contract.status);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.autorenew_rounded,
                      color: AppColors.primary, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        contract.planName.isNotEmpty
                            ? contract.planName
                            : 'AMC Contract',
                        style: tt.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      if (contract.serviceName.isNotEmpty)
                        Text(
                          contract.serviceName,
                          style: tt.bodySmall
                              ?.copyWith(color: AppColors.textSecondary),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusBg,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: statusColor,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ],
            ),

            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Divider(height: 1),
            ),

            // Detail rows
            if (contract.recurrenceInterval.isNotEmpty)
              _Row(
                icon: Icons.repeat_rounded,
                label: 'Service Interval',
                value: contract.recurrenceInterval,
              ),
            if (contract.originalTotal != null && contract.originalTotal! > 0)
              _Row(
                icon: Icons.receipt_outlined,
                label: 'Original Total',
                value: '₹${contract.originalTotal!.toStringAsFixed(2)}',
              ),
            if (contract.discountAmount != null && contract.discountAmount! > 0)
              _Row(
                icon: Icons.local_offer_outlined,
                label: 'Discount',
                value: _discountLabel(contract),
              ),
            if (contract.finalPrice != null && contract.finalPrice! > 0)
              _Row(
                icon: Icons.currency_rupee_rounded,
                label: 'Final AMC Price',
                value: '₹${contract.finalPrice!.toStringAsFixed(2)}',
              )
            else if (contract.pricePerVisit > 0)
              _Row(
                icon: Icons.currency_rupee_rounded,
                label: 'Price Per Visit',
                value: '₹${contract.pricePerVisit.toStringAsFixed(2)}',
              ),
            if (contract.quantity > 1)
              _Row(
                icon: Icons.devices_rounded,
                label: 'Units Covered',
                value: '${contract.quantity} units',
              ),
            if (contract.isRenewal)
              _Row(
                icon: Icons.autorenew_rounded,
                label: 'Contract Type',
                value: 'Renewal',
              ),
            _Row(
              icon: Icons.calendar_month_rounded,
              label: 'Started',
              value: _formatDate(contract.createdAt.toLocal()),
            ),
          ],
        ),
      ),
    );
  }

  String _discountLabel(AmcContractModel c) {
    final amt = c.discountAmount ?? 0;
    if (c.discountType == 'percentage' && c.discountValue != null) {
      return '−₹${amt.toStringAsFixed(2)} (${c.discountValue!.toStringAsFixed(0)}%)';
    }
    return '−₹${amt.toStringAsFixed(2)}';
  }

  (String, Color, Color) _statusMeta(String status) => switch (status) {
        'active' => ('Active', AppColors.success,
            AppColors.success.withValues(alpha: 0.12)),
        'paused' =>
          ('Paused', AppColors.warning, AppColors.warning.withValues(alpha: 0.12)),
        'completed' => ('Completed', AppColors.primary,
            AppColors.primaryLight),
        'cancelled' =>
          ('Cancelled', AppColors.error, AppColors.error.withValues(alpha: 0.1)),
        'cancellation_requested' => (
          'Cancellation Pending',
          const Color(0xFFC05621),
          const Color(0xFFFFF3E0)
        ),
        _ => ('Unknown', AppColors.textHint,
            AppColors.border),
      };

  String _formatDate(DateTime d) =>
      '${d.day} ${_months[d.month - 1]} ${d.year}';

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
}

class _Row extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _Row({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: tt.labelSmall
                        ?.copyWith(color: AppColors.textSecondary)),
                Text(value,
                    style: tt.bodySmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Visits progress bar ───────────────────────────────────────────────────────

class _VisitsProgress extends StatelessWidget {
  final AmcContractModel contract;

  const _VisitsProgress({required this.contract});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final total = contract.effectiveTotalVisits;
    final completed = contract.completedVisits;
    final remaining = contract.remainingVisits;
    final progress = total > 0 ? completed / total : 0.0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'VISITS OVERVIEW',
              style: tt.labelMedium?.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _VisitStat(
                  label: 'Total',
                  value: '$total',
                  color: AppColors.primary,
                ),
                const SizedBox(width: 4),
                Expanded(child: Container()),
                _VisitStat(
                  label: 'Completed',
                  value: '$completed',
                  color: AppColors.success,
                ),
                const SizedBox(width: 16),
                _VisitStat(
                  label: 'Remaining',
                  value: '$remaining',
                  color: remaining > 0
                      ? AppColors.warning
                      : AppColors.textHint,
                ),
              ],
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress.clamp(0.0, 1.0),
                minHeight: 8,
                backgroundColor: AppColors.border,
                color: AppColors.success,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '$completed of $total visits completed',
              style: tt.labelSmall?.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _VisitStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _VisitStat({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Column(
      children: [
        Text(
          value,
          style: tt.headlineSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(
          label,
          style: tt.labelSmall?.copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

// ── Visits list ───────────────────────────────────────────────────────────────

// Adds N calendar months to a UTC base date, clamping the day to the last day
// of the target month — mirrors PostgreSQL: start + N * interval '1 month'.
// e.g. 2026-07-30 + 7 months = 2027-02-28 (not 2027-03-02).
DateTime _addCalendarMonths(DateTime base, int months) {
  final total = (base.month - 1) + months;
  final targetYear = base.year + total ~/ 12;
  final targetMonth = total % 12 + 1;
  final daysInMonth = DateTime.utc(targetYear, targetMonth + 1, 0).day;
  return DateTime.utc(targetYear, targetMonth, base.day.clamp(1, daysInMonth));
}

// Computes the fixed planned due date for visit N using calendar arithmetic,
// matching the PostgreSQL trigger formula exactly.
DateTime? _computePlannedDate(
    DateTime createdAt, String? serviceInterval, int visitNumber) {
  if (serviceInterval == null) return null;
  final n = visitNumber - 1;
  final base = DateTime.utc(createdAt.year, createdAt.month, createdAt.day);
  return switch (serviceInterval) {
    'monthly'     => _addCalendarMonths(base, n),
    'quarterly'   => _addCalendarMonths(base, 3 * n),
    'half_yearly' => _addCalendarMonths(base, 6 * n),
    'yearly'      => _addCalendarMonths(base, 12 * n),
    _ => null,
  };
}

// Maps each visit booking to its slot using amc_visit_number exclusively.
// Bookings without a visit number are not placed — their slot renders as
// "Remaining". This prevents any positional guessing that would overwrite a
// completed visit with a pending one or vice-versa.
Map<int, AmcVisitModel> _buildVisitMap(List<AmcVisitModel> visits) {
  debugPrint('[AMC][Customer][VisitMap] Building from ${visits.length} visits:');
  for (final v in visits) {
    debugPrint('[AMC][Customer][VisitMap]   id=${v.id.length > 8 ? v.id.substring(0, 8) : v.id}  visitNumber=${v.visitNumber}  status=${v.status}');
  }
  final map = <int, AmcVisitModel>{};
  for (final v in visits) {
    final n = v.visitNumber;
    if (n != null && n >= 1) {
      // When two bookings share the same visit number (data anomaly), keep the
      // one with the more advanced status so a completed visit is never hidden.
      final existing = map[n];
      if (existing == null || _statusRank(v.status) > _statusRank(existing.status)) {
        map[n] = v;
      }
    }
  }
  debugPrint('[AMC][Customer][VisitMap] Final map: ${map.map((k, v) => MapEntry(k, v.status))}');
  return map;
}

int _statusRank(String status) => switch (status) {
      'completed' => 5,
      'awaiting_verification' => 4,
      'in_progress' || 'started' => 3,
      'assigned' || 'accepted' || 'en_route' => 2,
      'pending' => 1,
      _ => 0,
    };

class _VisitsList extends StatelessWidget {
  final AmcContractModel contract;

  const _VisitsList({required this.contract});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final total = contract.effectiveTotalVisits;

    // Render all contract slots; fall back to actual visit count when total
    // is 0 (shouldn't happen for valid contracts).
    final displayCount =
        total > 0 ? total : contract.visits.length;
    final visitMap = _buildVisitMap(contract.visits);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'VISIT HISTORY ($displayCount visits)',
              style: tt.labelMedium?.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 12),
            if (displayCount == 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded,
                        size: 16, color: AppColors.textHint),
                    const SizedBox(width: 8),
                    Text(
                      'No AMC visits yet.',
                      style: tt.bodySmall
                          ?.copyWith(color: AppColors.textHint),
                    ),
                  ],
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: displayCount,
                separatorBuilder: (_, _) =>
                    const Divider(height: 16, thickness: 0.5),
                itemBuilder: (_, i) {
                  final n = i + 1;
                  return _VisitRow(
                    visit: visitMap[n],
                    visitNumber: n,
                    plannedDueDate: _computePlannedDate(
                      contract.createdAt,
                      contract.serviceInterval,
                      n,
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _VisitRow extends StatelessWidget {
  // null means no booking exists for this slot yet.
  final AmcVisitModel? visit;
  final int visitNumber;
  final DateTime? plannedDueDate;

  const _VisitRow({
    required this.visit,
    required this.visitNumber,
    this.plannedDueDate,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    final badge = Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: visit != null ? AppColors.primaryLight : AppColors.border,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Text(
          '$visitNumber',
          style: tt.labelSmall?.copyWith(
            color: visit != null ? AppColors.primary : AppColors.textHint,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );

    // ── Placeholder row (no booking yet) ───────────────────────────────────
    if (visit == null) {
      final dueLine = plannedDueDate != null
          ? 'Visit #$visitNumber · Due: ${_formatDate(plannedDueDate!)}'
          : 'Visit #$visitNumber';
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          badge,
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              dueLine,
              style: tt.bodySmall?.copyWith(
                color: AppColors.textHint,
                fontWeight: FontWeight.w500,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'Remaining',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppColors.textHint,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      );
    }

    // ── Actual visit row ────────────────────────────────────────────────────
    final v = visit!;
    final (statusLabel, statusColor, statusBg) = _statusMeta(v.status);
    final scheduledStr =
        v.serviceDate != null ? _formatDate(v.serviceDate!) : null;
    final timeStr = v.timeSlot.isNotEmpty ? ' · ${v.timeSlot}' : '';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        badge,
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (scheduledStr != null)
                Text(
                  '$scheduledStr$timeStr',
                  style: tt.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                )
              else
                Text(
                  'Visit #$visitNumber',
                  style: tt.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                ),
              if (plannedDueDate != null)
                Text(
                  'Due: ${_formatDate(plannedDueDate!)}',
                  style: tt.labelSmall?.copyWith(color: AppColors.textSecondary),
                ),
              const SizedBox(height: 2),
              Text(
                '#${v.id.substring(0, 8)}',
                style:
                    tt.labelSmall?.copyWith(color: AppColors.textHint),
              ),
              if (v.vendorName != null && v.vendorName!.isNotEmpty)
                Text(
                  v.vendorName!,
                  style:
                      tt.labelSmall?.copyWith(color: AppColors.textSecondary),
                ),
              if (v.completedAt != null)
                Text(
                  'Completed: ${_formatDate(v.completedAt!.toLocal())}',
                  style: tt.labelSmall?.copyWith(
                    color: AppColors.success,
                    fontWeight: FontWeight.w500,
                  ),
                ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: statusBg,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            statusLabel,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: statusColor,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ],
    );
  }

  (String, Color, Color) _statusMeta(String status) => switch (status) {
        'completed' => ('Completed', AppColors.success,
            AppColors.success.withValues(alpha: 0.12)),
        'cancelled' => ('Cancelled', AppColors.error,
            AppColors.error.withValues(alpha: 0.1)),
        'in_progress' || 'started' => ('In Progress',
            const Color(0xFFFF6D00),
            const Color(0xFFFF6D00).withValues(alpha: 0.1)),
        'awaiting_verification' => ('Awaiting OTP', AppColors.warning,
            AppColors.warning.withValues(alpha: 0.12)),
        'assigned' || 'accepted' || 'en_route' => ('Scheduled',
            AppColors.primary, AppColors.primaryLight),
        _ => ('Pending', AppColors.warning,
            AppColors.warning.withValues(alpha: 0.12)),
      };

  String _formatDate(DateTime d) =>
      '${d.day} ${_months[d.month - 1]} ${d.year}';

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
}
