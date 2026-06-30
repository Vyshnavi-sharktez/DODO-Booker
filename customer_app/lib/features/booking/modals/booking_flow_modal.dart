import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../features/bookings/utils/my_bookings_launcher.dart';
import '../../../core/widgets/app_modal_dialog.dart';
import '../../../models/service_model.dart';
import '../../../models/address_model.dart';
import '../../../models/time_slot_model.dart';
import '../../../models/coupon_model.dart';
import '../../../features/address/modals/address_form_modal.dart';
import '../services/booking_providers.dart';
import '../services/coupon_providers.dart';
import '../widgets/date_selector.dart';
import '../widgets/time_slot_card.dart';
import '../widgets/booking_summary_card.dart';
import '../widgets/available_coupons_sheet.dart';

/// Desktop booking flow rendered inside [PageSheet].
/// Uses the same light surface + AppColors design language as Profile dialogs.
/// Mobile keeps the sequential [AppModalDialog] flow unchanged.
class BookingFlowModal extends ConsumerStatefulWidget {
  final ServiceModel service;
  const BookingFlowModal({super.key, required this.service});

  @override
  ConsumerState<BookingFlowModal> createState() => _BookingFlowModalState();
}

class _BookingFlowModalState extends ConsumerState<BookingFlowModal>
    with SingleTickerProviderStateMixin {
  int _step = 0; // 0=Address  1=DateTime  2=Summary  3=Payment
  AddressModel? _address;
  DateTime _date = DateTime.now();
  TimeSlotModel? _slot;
  bool _showSuccess = false;
  bool _isCreating = false;
  String? _errorMessage;

  final _couponCtrl = TextEditingController();
  bool _applyingCoupon = false;
  String? _couponError;

  late final AnimationController _successCtrl;
  late final Animation<double> _successScale;

  String get _dateKey =>
      '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}';

  double get _subtotal => widget.service.startingPrice * 1.18;

  @override
  void initState() {
    super.initState();
    _successCtrl = AnimationController(
      duration: const Duration(milliseconds: 650),
      vsync: this,
    );
    _successScale =
        CurvedAnimation(parent: _successCtrl, curve: Curves.elasticOut);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(selectedCouponProvider.notifier).state = null;
    });
  }

  @override
  void dispose() {
    _couponCtrl.dispose();
    _successCtrl.dispose();
    super.dispose();
  }

  // ── Navigation ────────────────────────────────────────────────────────────────

  void _onBack() {
    if (_step == 0) {
      Navigator.of(context).maybePop();
    } else {
      setState(() {
        _step--;
        _errorMessage = null;
      });
    }
  }

  Future<void> _onNext(double total) async {
    if (_step == 0 && _address == null) {
      final addrs = ref.read(addressesProvider).valueOrNull ?? [];
      if (addrs.isEmpty) return;
      _address =
          addrs.firstWhere((a) => a.isDefault, orElse: () => addrs.first);
    }

    if (_step < 3) {
      setState(() {
        _step++;
        _errorMessage = null;
      });
      return;
    }

    setState(() {
      _isCreating = true;
      _errorMessage = null;
    });

    final selectedCoupon = ref.read(selectedCouponProvider);
    final discountAmount = selectedCoupon?.calculateDiscount(_subtotal) ?? 0.0;

    try {
      await ref.read(bookingServiceProvider).createBooking(
            service: widget.service,
            address: _address!,
            date: _date,
            slot: _slot!,
            couponId: selectedCoupon?.id,
            discountAmount: discountAmount,
          );
      ref.read(selectedCouponProvider.notifier).state = null;
      if (!mounted) return;
      setState(() {
        _isCreating = false;
        _showSuccess = true;
      });
      _successCtrl.forward();
    } catch (e) {
      ref.read(selectedCouponProvider.notifier).state = null;
      if (!mounted) return;
      setState(() {
        _isCreating = false;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  // ── Address helpers ───────────────────────────────────────────────────────────

  Future<void> _addNewAddress() async {
    final addr = await AppModalDialog.show<AddressModel>(
      context: context,
      child: const AddressFormModal(),
    );
    if (!mounted || addr == null) return;
    setState(() => _address = addr);
  }

  // ── Coupon helpers ────────────────────────────────────────────────────────────

  Future<void> _applyCoupon() async {
    final code = _couponCtrl.text.trim().toUpperCase();
    if (code.isEmpty) {
      setState(() => _couponError = 'Enter a coupon code.');
      return;
    }
    setState(() {
      _applyingCoupon = true;
      _couponError = null;
    });
    try {
      final coupons = await ref.read(activeCouponsProvider.future);
      final found =
          coupons.where((c) => c.code.toUpperCase() == code).firstOrNull;
      if (found == null) {
        setState(() => _couponError = 'Coupon code not found.');
        return;
      }
      final err = found.validate(_subtotal);
      if (err != null) {
        setState(() => _couponError = err);
        return;
      }
      ref.read(selectedCouponProvider.notifier).state = found;
      setState(() => _couponError = null);
    } catch (_) {
      setState(() => _couponError = 'Could not verify coupon. Try again.');
    } finally {
      if (mounted) setState(() => _applyingCoupon = false);
    }
  }

  void _removeCoupon() {
    ref.read(selectedCouponProvider.notifier).state = null;
    _couponCtrl.clear();
    setState(() => _couponError = null);
  }

  Future<void> _showCouponsSheet() async {
    setState(() => _couponError = null);
    final coupon = await showModalBottomSheet<CouponModel>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AvailableCouponsSheet(
        subtotal: _subtotal,
        selectedCoupon: ref.read(selectedCouponProvider),
      ),
    );
    if (coupon == null || !mounted) return;
    _couponCtrl.text = coupon.code;
    ref.read(selectedCouponProvider.notifier).state = coupon;
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final selectedCoupon = ref.watch(selectedCouponProvider);
    final discount = selectedCoupon?.calculateDiscount(_subtotal) ?? 0.0;
    final total = (_subtotal - discount).clamp(0.0, double.infinity);

    if (_showSuccess) return _buildSuccessView();

    return PopScope(
      canPop: !_isCreating,
      child: Column(
        children: [
          _buildStepper(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
              child: _buildStepContent(
                  selectedCoupon: selectedCoupon, discount: discount),
            ),
          ),
          if (_errorMessage != null) _buildErrorBanner(),
          _buildFooter(total: total),
        ],
      ),
    );
  }

  // ── Compact stepper ───────────────────────────────────────────────────────────

  Widget _buildStepper() {
    const labels = ['Address', 'Date & Time', 'Summary', 'Payment'];
    return Container(
      padding: const EdgeInsets.fromLTRB(40, 14, 40, 12),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.divider, width: 0.8)),
      ),
      child: Row(
        children: List.generate(labels.length * 2 - 1, (i) {
          if (i.isOdd) {
            final completed = i ~/ 2 < _step;
            return Expanded(
              child: Container(
                height: 1,
                margin: const EdgeInsets.only(bottom: 18),
                color: completed ? AppColors.primary : AppColors.border,
              ),
            );
          }
          final idx = i ~/ 2;
          final isCompleted = idx < _step;
          final isCurrent = idx == _step;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isCompleted ? AppColors.primary : Colors.transparent,
                  border: Border.all(
                    color: (isCompleted || isCurrent)
                        ? AppColors.primary
                        : AppColors.border,
                    width: isCompleted ? 0 : 1.5,
                  ),
                ),
                child: Center(
                  child: isCompleted
                      ? const Icon(Icons.check_rounded,
                          size: 13, color: Colors.white)
                      : Text(
                          '${idx + 1}',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: isCurrent
                                ? AppColors.primary
                                : AppColors.textHint,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                labels[idx],
                style: TextStyle(
                  fontSize: 10,
                  fontWeight:
                      isCurrent ? FontWeight.w700 : FontWeight.w400,
                  color: (isCompleted || isCurrent)
                      ? AppColors.primary
                      : AppColors.textHint,
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  // ── Step content dispatcher ───────────────────────────────────────────────────

  Widget _buildStepContent({
    required CouponModel? selectedCoupon,
    required double discount,
  }) {
    return switch (_step) {
      0 => _buildAddressStep(),
      1 => _buildDateTimeStep(),
      2 => _buildSummaryStep(selectedCoupon: selectedCoupon, discount: discount),
      3 => _buildPaymentStep(),
      _ => const SizedBox.shrink(),
    };
  }

  // ── Step 0: Address ───────────────────────────────────────────────────────────

  Widget _buildAddressStep() {
    final asyncAddresses = ref.watch(addressesProvider);
    return asyncAddresses.when(
      loading: () => _Skeleton(count: 3, height: 72),
      error: (e, _) => _ErrorState(
        message: 'Could not load addresses',
        onRetry: () => ref.read(addressNotifierProvider.notifier).load(),
      ),
      data: (addresses) {
        if (addresses.isEmpty) {
          return _EmptyState(
            icon: Icons.location_off_rounded,
            title: 'No saved addresses',
            subtitle: 'Add an address to continue booking.',
            actionLabel: 'Add Address',
            onAction: _addNewAddress,
          );
        }
        final effective = _address ??
            addresses.firstWhere((a) => a.isDefault,
                orElse: () => addresses.first);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SectionLabel('Delivery address'),
            const SizedBox(height: 10),
            ...addresses.map(
              (a) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _CompactAddressCard(
                  address: a,
                  isSelected: effective.id == a.id,
                  onTap: () => setState(() => _address = a),
                ),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _addNewAddress,
              icon: const Icon(Icons.add_location_alt_rounded, size: 16),
              label: const Text('Add New Address'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
                side: BorderSide(color: AppColors.primary, width: 1.5),
              ),
            ),
          ],
        );
      },
    );
  }

  // ── Step 1: Date & Time ───────────────────────────────────────────────────────

  Widget _buildDateTimeStep() {
    final slotsAsync = ref.watch(timeSlotsProvider(_dateKey));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel('Select date'),
        const SizedBox(height: 10),
        DateSelector(
          selectedDate: _date,
          onDateSelected: (d) => setState(() {
            _date = d;
            _slot = null;
          }),
        ),
        const SizedBox(height: 20),
        const Divider(color: AppColors.divider, height: 1),
        const SizedBox(height: 20),
        _SectionLabel('Select time slot'),
        const SizedBox(height: 10),
        slotsAsync.when(
          loading: () => Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(
              12,
              (_) => Container(
                width: 88,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.shimmerBase,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
          error: (e, st) => Text(
            'Could not load time slots.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          data: (slots) => _SlotsGrid(
            slots: slots,
            selected: _slot,
            onSelect: (s) => setState(() => _slot = s),
          ),
        ),
      ],
    );
  }

  // ── Step 2: Summary + Coupon ──────────────────────────────────────────────────

  Widget _buildSummaryStep({
    required CouponModel? selectedCoupon,
    required double discount,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BookingSummaryCard(
          service: widget.service,
          address: _address!,
          date: _date,
          slot: _slot!,
          discountAmount: discount,
          couponCode: selectedCoupon?.code,
        ),
        const SizedBox(height: 16),

        // Coupon section
        _SectionLabel('Have a coupon?'),
        const SizedBox(height: 10),

        if (selectedCoupon == null) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _couponCtrl,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    hintText: 'Enter coupon code',
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    border:
                        OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    errorText: _couponError,
                  ),
                  onSubmitted: (_) => _applyCoupon(),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 44,
                child: FilledButton(
                  onPressed: _applyingCoupon ? null : _applyCoupon,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                  ),
                  child: _applyingCoupon
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Apply',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: _showCouponsSheet,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.local_offer_outlined,
                    size: 12, color: AppColors.primary),
                const SizedBox(width: 4),
                Text(
                  'View available coupons',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ] else ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.success.withAlpha(18),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.success.withAlpha(80)),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle_rounded,
                    color: AppColors.success, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        selectedCoupon.code,
                        style: const TextStyle(
                            color: AppColors.success,
                            fontWeight: FontWeight.w700,
                            fontSize: 13),
                      ),
                      Text(
                        '${selectedCoupon.discountLabel} applied',
                        style: const TextStyle(
                            color: AppColors.success, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: _removeCoupon,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    foregroundColor: AppColors.error,
                  ),
                  child: const Text('Remove', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 12),
        Row(
          children: [
            const Icon(Icons.lock_rounded, size: 13, color: AppColors.success),
            const SizedBox(width: 5),
            Text('Secure checkout',
                style: TextStyle(fontSize: 11, color: AppColors.success)),
          ],
        ),
      ],
    );
  }

  // ── Step 3: Payment ───────────────────────────────────────────────────────────

  Widget _buildPaymentStep() {
    final coupon = ref.read(selectedCouponProvider);
    final total = (_subtotal - (coupon?.calculateDiscount(_subtotal) ?? 0.0))
        .clamp(0.0, double.infinity);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Amount summary
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.primaryLight,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total Amount Due',
                style: TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              Text(
                '₹${total.toStringAsFixed(2)}',
                style: TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _SectionLabel('Select payment method'),
        const SizedBox(height: 10),
        _PaymentOption(
          icon: Icons.account_balance_wallet_rounded,
          label: 'UPI / QR Code',
          tag: 'Recommended',
        ),
        const SizedBox(height: 8),
        const _PaymentOption(
            icon: Icons.credit_card_rounded, label: 'Credit / Debit Card'),
        const SizedBox(height: 8),
        const _PaymentOption(
            icon: Icons.account_balance_rounded, label: 'Net Banking'),
        const SizedBox(height: 8),
        const _PaymentOption(
            icon: Icons.money_rounded, label: 'Cash on Service'),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.warning.withAlpha(18),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.warning.withAlpha(70)),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline_rounded,
                  size: 14, color: AppColors.warning),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Payment gateway integration is coming soon. '
                  'Tap Confirm below to create a test booking.',
                  style: TextStyle(
                      fontSize: 11, color: const Color(0xFFB45309)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Error banner ──────────────────────────────────────────────────────────────

  Widget _buildErrorBanner() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.error.withAlpha(18),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.error.withAlpha(80)),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 16, color: AppColors.error),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _errorMessage!,
                style: const TextStyle(fontSize: 12, color: AppColors.error),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Footer ────────────────────────────────────────────────────────────────────

  Widget _buildFooter({required double total}) {
    final isFirstStep = _step == 0;
    final label = switch (_step) {
      3 => 'Confirm Booking',
      2 => 'Proceed to Payment',
      _ => 'Continue',
    };

    final canContinue = switch (_step) {
      0 => ref.read(addressesProvider).valueOrNull?.isNotEmpty ?? false,
      1 => _slot != null,
      _ => true,
    };

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border:
            Border(top: BorderSide(color: AppColors.divider, width: 0.8)),
      ),
      child: Row(
        children: [
          TextButton(
            onPressed: _isCreating ? null : _onBack,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
            child: Text(isFirstStep ? 'Cancel' : '← Back'),
          ),
          const Spacer(),
          FilledButton(
            onPressed: (canContinue && !_isCreating) ? () => _onNext(total) : null,
            style: FilledButton.styleFrom(
              minimumSize: const Size(140, 44),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: _isCreating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: Colors.white),
                  )
                : Text(
                    label,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700),
                  ),
          ),
        ],
      ),
    );
  }

  // ── Success view ──────────────────────────────────────────────────────────────

  Widget _buildSuccessView() {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            child: Column(
              children: [
                const SizedBox(height: 32),
                ScaleTransition(
                  scale: _successScale,
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: AppColors.success,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.success.withAlpha(60),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: const Icon(Icons.check_rounded,
                        size: 38, color: Colors.white),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Booking Confirmed!',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  "We'll see you on ${_dateStr()}",
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: AppColors.textSecondary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 28),
                _buildSuccessCard(),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border:
                Border(top: BorderSide(color: AppColors.divider, width: 0.8)),
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Close'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    openMyBookings(context);
                  },
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('View Bookings',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSuccessCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
              color: Color(0x08000000), blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SuccessRow(
              icon: Icons.home_repair_service_rounded,
              label: 'Service',
              value: widget.service.name),
          const Divider(color: AppColors.divider, height: 20),
          _SuccessRow(
              icon: Icons.location_on_rounded,
              label: 'Address',
              value: '${_address!.line1}, ${_address!.city}'),
          const Divider(color: AppColors.divider, height: 20),
          _SuccessRow(
              icon: Icons.calendar_today_rounded,
              label: 'Date',
              value: _dateStr()),
          const Divider(color: AppColors.divider, height: 20),
          _SuccessRow(
              icon: Icons.access_time_rounded,
              label: 'Time',
              value: _slot?.label ?? '—'),
        ],
      ),
    );
  }

  String _dateStr() {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${_date.day} ${months[_date.month - 1]} ${_date.year}';
  }
}

// ── Section label ──────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
    );
  }
}

// ── Compact address card (desktop booking flow only) ───────────────────────────

class _CompactAddressCard extends StatelessWidget {
  final AddressModel address;
  final bool isSelected;
  final VoidCallback onTap;

  const _CompactAddressCard({
    required this.address,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isSelected ? AppColors.primary : AppColors.border,
          width: isSelected ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.primary.withAlpha(15)
                      : AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _iconForLabel(address.label),
                  size: 16,
                  color: isSelected
                      ? AppColors.primary
                      : AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          address.label,
                          style: tt.labelMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: isSelected
                                ? AppColors.primary
                                : AppColors.textPrimary,
                          ),
                        ),
                        if (address.isDefault) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: AppColors.success.withAlpha(20),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              'Default',
                              style: TextStyle(
                                fontSize: 9,
                                color: AppColors.success,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${address.line1}, ${address.city}',
                      style: tt.bodySmall?.copyWith(
                          color: AppColors.textSecondary, fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: isSelected
                    ? const Icon(Icons.check_circle_rounded,
                        color: AppColors.primary, size: 18)
                    : Icon(Icons.radio_button_unchecked_rounded,
                        color: AppColors.border, size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconForLabel(String label) => switch (label.toLowerCase()) {
        'home' => Icons.home_rounded,
        'work' || 'office' => Icons.work_rounded,
        _ => Icons.location_on_rounded,
      };
}

// ── Time slots grid ────────────────────────────────────────────────────────────

class _SlotsGrid extends StatelessWidget {
  final List<TimeSlotModel> slots;
  final TimeSlotModel? selected;
  final ValueChanged<TimeSlotModel> onSelect;

  const _SlotsGrid(
      {required this.slots, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final grouped = {
      SlotPeriod.morning:
          slots.where((s) => s.period == SlotPeriod.morning).toList(),
      SlotPeriod.afternoon:
          slots.where((s) => s.period == SlotPeriod.afternoon).toList(),
      SlotPeriod.evening:
          slots.where((s) => s.period == SlotPeriod.evening).toList(),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: grouped.entries.map((entry) {
        final periodSlots = entry.value;
        if (periodSlots.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(_periodIcon(entry.key),
                      size: 13, color: AppColors.textSecondary),
                  const SizedBox(width: 5),
                  Text(
                    entry.key.label,
                    style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: periodSlots
                    .map((slot) => TimeSlotCard(
                          slot: slot,
                          isSelected: selected?.id == slot.id,
                          onTap: slot.isAvailable ? () => onSelect(slot) : null,
                        ))
                    .toList(),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  IconData _periodIcon(SlotPeriod p) => switch (p) {
        SlotPeriod.morning => Icons.wb_sunny_outlined,
        SlotPeriod.afternoon => Icons.wb_cloudy_outlined,
        SlotPeriod.evening => Icons.nights_stay_outlined,
      };
}

// ── Payment option ─────────────────────────────────────────────────────────────

class _PaymentOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? tag;

  const _PaymentOption({required this.icon, required this.label, this.tag});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () {},
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.primary, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                  style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
            ),
            if (tag != null) ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.success.withAlpha(18),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  tag!,
                  style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.success,
                      fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 4),
            ],
            Icon(Icons.chevron_right_rounded,
                size: 18, color: AppColors.textHint),
          ],
        ),
      ),
    );
  }
}

// ── State helpers ──────────────────────────────────────────────────────────────

class _Skeleton extends StatelessWidget {
  final int count;
  final double height;
  const _Skeleton({required this.count, required this.height});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        count,
        (_) => Container(
          height: height,
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: AppColors.shimmerBase,
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded,
              size: 40, color: AppColors.error),
          const SizedBox(height: 10),
          Text(message,
              style:
                  TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          const SizedBox(height: 12),
          FilledButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onAction;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: AppColors.textHint),
          const SizedBox(height: 12),
          Text(title,
              style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(subtitle,
              style: tt.bodySmall?.copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: onAction,
            style: FilledButton.styleFrom(minimumSize: const Size(160, 44)),
            child: Text(actionLabel,
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

// ── Success detail row ─────────────────────────────────────────────────────────

class _SuccessRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _SuccessRow(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: AppColors.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: tt.labelSmall?.copyWith(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w500)),
              const SizedBox(height: 2),
              Text(value,
                  style: tt.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ],
    );
  }
}
