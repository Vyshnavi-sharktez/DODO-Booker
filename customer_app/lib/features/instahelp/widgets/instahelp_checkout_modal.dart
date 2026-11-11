import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/page_sheet.dart';
import '../../../models/address_model.dart';
import '../../address/screens/address_screen.dart';
import '../../address/services/address_providers.dart';
import '../../booking/services/razorpay_service.dart';
import '../../booking/widgets/booking_success_dialog.dart';
import '../../bookings/services/bookings_providers.dart';
import '../../bookings/utils/my_bookings_launcher.dart';
import '../../cart/widgets/payment_selection_sheet.dart';
import '../../preferred_vendor/providers/preferred_vendor_provider.dart';
import '../models/instahelp_duration_model.dart';
import '../models/instahelp_financial_config_model.dart';
import '../providers/instahelp_providers.dart';
import '../services/instahelp_service.dart';

class InstaHelpCheckoutModal extends ConsumerStatefulWidget {
  final String modeId;
  final String modeType;
  final InstaHelpDurationModel duration;
  final DateTime? preselectedDate;
  final String? preselectedSlot;
  final String? assignedVendorId;

  const InstaHelpCheckoutModal({
    super.key,
    required this.modeId,
    required this.modeType,
    required this.duration,
    this.preselectedDate,
    this.preselectedSlot,
    this.assignedVendorId,
  });

  static Future<void> open(
    BuildContext context, {
    required String modeId,
    required String modeType,
    required InstaHelpDurationModel duration,
    DateTime? preselectedDate,
    String? preselectedSlot,
    String? assignedVendorId,
  }) {
    final modal = InstaHelpCheckoutModal(
      modeId: modeId,
      modeType: modeType,
      duration: duration,
      preselectedDate: preselectedDate,
      preselectedSlot: preselectedSlot,
      assignedVendorId: assignedVendorId,
    );
    if (MediaQuery.sizeOf(context).width >= 768) {
      return PageSheet.show(context, title: 'Checkout', child: modal);
    }
    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: Text('Checkout',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
            backgroundColor: AppColors.surface,
            elevation: 0,
          ),
          body: modal,
        ),
      ),
    );
  }

  @override
  ConsumerState<InstaHelpCheckoutModal> createState() =>
      _InstaHelpCheckoutModalState();
}

class _InstaHelpCheckoutModalState
    extends ConsumerState<InstaHelpCheckoutModal> {
  AddressModel? _selectedAddress;
  late DateTime? _selectedDate;
  late String? _selectedSlot;
  bool _placing = false;
  String? _error;

  // Preferred vendor
  String? _pvId;
  String? _pvName;
  double _pvFee = 0.0;

  bool get _isScheduled => widget.modeType == 'scheduled';
  bool get _hasPreselectedDate => widget.preselectedDate != null;
  bool get _hasPreselectedSlot => widget.preselectedSlot != null;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.preselectedDate;
    _selectedSlot = widget.preselectedSlot;
  }

  final _fmt = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  );

  static const _monthNames = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _formatDate(DateTime d) {
    final now = DateTime.now();
    if (d.year == now.year && d.month == now.month && d.day == now.day) {
      return 'Today';
    }
    final tomorrow = now.add(const Duration(days: 1));
    if (d.year == tomorrow.year &&
        d.month == tomorrow.month &&
        d.day == tomorrow.day) {
      return 'Tomorrow';
    }
    return '${d.day} ${_monthNames[d.month - 1]} ${d.year}';
  }

  static List<String> _generateSlots() {
    final slots = <String>[];
    for (int h = 8; h <= 20; h++) {
      for (int m = 0; m < 60; m += 30) {
        final mm = m.toString().padLeft(2, '0');
        final ampm = h < 12 ? 'AM' : 'PM';
        final h12 = h > 12 ? h - 12 : (h == 0 ? 12 : h);
        slots.add('$h12:$mm $ampm');
      }
      if (h == 20) break;
    }
    return slots;
  }

  static final _slots = _generateSlots();

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 90)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: Theme.of(ctx)
              .colorScheme
              .copyWith(primary: AppColors.primary),
        ),
        child: child!,
      ),
    );
    if (picked != null && mounted) {
      setState(() {
        _selectedDate = picked;
        _selectedSlot = null;
      });
    }
  }

  Future<void> _changeAddress() async {
    final result = await PageSheet.show<AddressModel>(
      context,
      title: 'Select Address',
      child: const AddressScreen(inModal: true, pickMode: true),
    );
    if (!mounted) return;
    setState(() => _selectedAddress = result ?? _selectedAddress);
    ref.invalidate(addressNotifierProvider);
  }

  Future<void> _placeBooking(
      InstaHelpFinancialConfigModel? financialConfig) async {
    if (_selectedAddress == null) {
      _showValidation(
          'Address Required', 'Please select a service address before proceeding.');
      return;
    }
    if (_isScheduled && _selectedDate == null) {
      _showValidation(
          'Date Required', 'Please select a service date before proceeding.');
      return;
    }
    if (_isScheduled && _selectedSlot == null) {
      _showValidation(
          'Time Slot Required', 'Please select a time slot before proceeding.');
      return;
    }

    // Show payment method selection sheet before booking.
    final paymentMethod = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const PaymentSelectionSheet(),
    );
    if (!mounted || paymentMethod == null) return;

    setState(() {
      _placing = true;
      _error = null;
    });
    try {
      final date = _isScheduled ? _selectedDate! : DateTime.now();
      final slot = _isScheduled ? (_selectedSlot ?? 'Flexible') : 'Immediate';
      final effectiveVendorId = widget.assignedVendorId ?? _pvId;
      final effectiveFee = widget.assignedVendorId != null ? 0.0 : _pvFee;

      final booking = await InstaHelpService().createBooking(
        modeId: widget.modeId,
        modeType: widget.modeType,
        duration: widget.duration,
        address: _selectedAddress!,
        date: date,
        scheduledTime: slot,
        paymentMethod: paymentMethod,
        financialConfig: financialConfig,
        preferredVendorId: effectiveVendorId,
        preferredVendorFee: effectiveFee,
      );
      if (!mounted) return;

      // ── Razorpay for online payments ────────────────────────────────────────
      if (paymentMethod == 'online') {
        late RazorpayCallbackData result;
        try {
          result = await RazorpayService().launchCheckout(booking.id);
        } catch (e) {
          try {
            await ref.read(bookingsServiceProvider).cancelBooking(
              booking.id, reason: 'payment_failed');
          } catch (_) {}
          if (!mounted) return;
          setState(() => _error = 'Payment could not be initiated. Booking cancelled.');
          return;
        }

        if (result.status == 'external_wallet') {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(
                'Please complete payment via '
                '${result.walletName ?? 'external wallet'}. Your booking is saved.',
              ),
            ));
          }
          return;
        }

        if (result.status != 'success') {
          try {
            await ref.read(bookingsServiceProvider).cancelBooking(
              booking.id, reason: 'payment_failed');
          } catch (_) {}
          if (!mounted) return;
          setState(() => _error = 'Payment was cancelled. Booking removed.');
          return;
        }

        try {
          await RazorpayService().verifyPayment(
            bookingId: booking.id,
            paymentId: result.paymentId!,
            orderId: result.orderId!,
            signature: result.signature!,
          );
        } catch (e) {
          if (mounted) {
            showDialog<void>(
              context: context,
              builder: (ctx) => AlertDialog(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                title: const Text('Verification Failed'),
                content: const Text(
                  'Payment verification failed. Your booking has been saved.\n\n'
                  'If you were charged, please contact support with your booking ID.',
                ),
                actions: [
                  FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('OK'),
                  ),
                ],
              ),
            );
          }
          return;
        }
      }

      ref.invalidate(myBookingsProvider);
      if (!mounted) return;
      final navigator = Navigator.of(context);
      // ignore: use_build_context_synchronously
      await showBookingSuccessDialog(
        context,
        booking,
        onClose: () => navigator.popUntil((r) => r.isFirst),
        onViewBookings: () {
          navigator.popUntil((r) => r.isFirst);
          openMyBookings(navigator.context);
        },
      );
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceFirst('Exception: ', '');
      setState(() => _error = msg.isNotEmpty ? msg : 'Booking failed. Please try again.');
    } finally {
      if (mounted) setState(() => _placing = false);
    }
  }

  void _showValidation(String title, String message) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        content: Text(message,
            style: const TextStyle(fontSize: 14, height: 1.5)),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final addressAsync = ref.watch(addressNotifierProvider);
    final financialAsync =
        ref.watch(instaHelpFinancialConfigProvider(widget.modeId));
    final basePrice = widget.duration.finalPrice;

    // Only fall back to zero AFTER the stream has emitted (hasValue).
    // While loading, treat as zero so the price shows base price.
    final configLoaded = financialAsync.hasValue;
    final cfg = configLoaded
        ? (financialAsync.value ?? InstaHelpFinancialConfigModel.zero(widget.modeId))
        : InstaHelpFinancialConfigModel.zero(widget.modeId);
    final surgeAmt = cfg.surgeAmount(basePrice);
    final scAmt = cfg.serviceChargeAmount(basePrice);
    final gstAmt = cfg.gstAmount(basePrice);
    final totalPrice = cfg.totalAmount(basePrice) + _pvFee;
    final financialConfig = financialAsync.value;

    // Preferred vendors for InstaHelp (global flag, location-filtered)
    final pvKey = _selectedAddress?.hasCoordinates == true
        ? (lat: _selectedAddress!.latitude!, lng: _selectedAddress!.longitude!)
        : null;
    final pvAsync = pvKey != null
        ? ref.watch(globalPreferredVendorsProvider(pvKey))
        : null;

    // Auto-select default address
    addressAsync.whenData((list) {
      if (list.isEmpty) return;
      final stillValid = _selectedAddress != null &&
          list.any((a) => a.id == _selectedAddress!.id);
      if (!stillValid) {
        final def =
            list.firstWhere((a) => a.isDefault, orElse: () => list.first);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _selectedAddress = def);
        });
      }
    });

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            children: [
              // ── Order Summary ───────────────────────────────────────────────
              _SectionCard(
                title: 'Order Summary',
                trailing: Text(
                  '1',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppColors.gold.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.flash_on_rounded,
                              color: AppColors.goldDeep, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'InstaHelp – ${widget.duration.label}',
                                style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                _fmt.format(basePrice),
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          _fmt.format(basePrice),
                          style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ── Service Address ─────────────────────────────────────────────
              _SectionCard(
                title: 'Service Address',
                child: addressAsync.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(12),
                    child: Center(
                        child:
                            CircularProgressIndicator(strokeWidth: 2)),
                  ),
                  error: (_, _) => Text(
                    'Could not load addresses',
                    style: TextStyle(color: AppColors.error, fontSize: 13),
                  ),
                  data: (list) {
                    if (list.isEmpty) {
                      return OutlinedButton.icon(
                        onPressed: _changeAddress,
                        icon: const Icon(Icons.add_rounded, size: 16),
                        label: const Text('Add Address'),
                      );
                    }
                    final addr = (_selectedAddress != null &&
                            list.any(
                                (a) => a.id == _selectedAddress!.id))
                        ? _selectedAddress!
                        : list.firstWhere((a) => a.isDefault,
                            orElse: () => list.first);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.radio_button_checked_rounded,
                              size: 18,
                              color: AppColors.primary,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        addr.label,
                                        style: GoogleFonts.poppins(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      if (addr.isDefault) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding:
                                              const EdgeInsets.symmetric(
                                                  horizontal: 6,
                                                  vertical: 2),
                                          decoration: BoxDecoration(
                                            color: AppColors.primaryLight,
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            'Default',
                                            style: GoogleFonts.poppins(
                                              fontSize: 10,
                                              color: AppColors.primary,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  Text(
                                    addr.fullAddress,
                                    style: GoogleFonts.poppins(
                                      fontSize: 12,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        TextButton.icon(
                          onPressed: _changeAddress,
                          icon: const Icon(Icons.swap_horiz_rounded,
                              size: 16),
                          label: const Text('Change Address'),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4),
                            foregroundColor: AppColors.primary,
                            textStyle: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600),
                            tapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),

              // ── Date & Time (scheduled only) ────────────────────────────────
              if (_isScheduled) ...[
                _SectionCard(
                  title: 'Service Date',
                  child: _hasPreselectedDate
                      ? _ReadOnlyRow(
                          icon: Icons.calendar_today_rounded,
                          text: _formatDate(_selectedDate!),
                        )
                      : GestureDetector(
                          onTap: _pickDate,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 13),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: _selectedDate != null
                                    ? AppColors.primary
                                    : AppColors.border,
                                width: _selectedDate != null ? 1.5 : 1,
                              ),
                              borderRadius: BorderRadius.circular(10),
                              color: _selectedDate != null
                                  ? AppColors.primary.withAlpha(10)
                                  : AppColors.surfaceVariant,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.calendar_today_rounded,
                                  size: 18,
                                  color: _selectedDate != null
                                      ? AppColors.primary
                                      : AppColors.textHint,
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  _selectedDate != null
                                      ? _formatDate(_selectedDate!)
                                      : 'Select a date',
                                  style: GoogleFonts.poppins(
                                    fontSize: 14,
                                    color: _selectedDate != null
                                        ? AppColors.textPrimary
                                        : AppColors.textHint,
                                    fontWeight: _selectedDate != null
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                  ),
                                ),
                                const Spacer(),
                                const Icon(Icons.chevron_right_rounded,
                                    size: 18, color: AppColors.textHint),
                              ],
                            ),
                          ),
                        ),
                ),
                const SizedBox(height: 16),

                _SectionCard(
                  title: 'Time Slot',
                  child: _hasPreselectedSlot
                      ? _ReadOnlyRow(
                          icon: Icons.access_time_rounded,
                          text: _selectedSlot!,
                        )
                      : (_selectedDate == null
                          ? Text(
                              'Select a date first.',
                              style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  color: AppColors.textHint),
                            )
                          : Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: _slots.map((slot) {
                                final isSel = slot == _selectedSlot;
                                return GestureDetector(
                                  onTap: () =>
                                      setState(() => _selectedSlot = slot),
                                  child: AnimatedContainer(
                                    duration:
                                        const Duration(milliseconds: 150),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: isSel
                                          ? AppColors.primary
                                          : AppColors.surface,
                                      borderRadius:
                                          BorderRadius.circular(8),
                                      border: Border.all(
                                        color: isSel
                                            ? AppColors.primary
                                            : AppColors.border,
                                      ),
                                    ),
                                    child: Text(
                                      slot,
                                      style: GoogleFonts.poppins(
                                        fontSize: 12,
                                        fontWeight: isSel
                                            ? FontWeight.w700
                                            : FontWeight.w400,
                                        color: isSel
                                            ? Colors.white
                                            : AppColors.textPrimary,
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            )),
                ),
                const SizedBox(height: 16),
              ],

              // ── Preferred Vendors ─────────────────────────────────────────
              if (pvAsync != null)
                pvAsync.when(
                  loading: () => const SizedBox.shrink(),
                  error: (_, _) => const SizedBox.shrink(),
                  data: (vendors) {
                    if (vendors.isEmpty) return const SizedBox.shrink();
                    final dateForBusy = _isScheduled
                        ? (_selectedDate ?? DateTime.now())
                        : DateTime.now();
                    final dateStr =
                        '${dateForBusy.year}-${dateForBusy.month.toString().padLeft(2, '0')}-${dateForBusy.day.toString().padLeft(2, '0')}';
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SectionCard(
                          title: 'Preferred Vendors',
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.gold.withAlpha(24),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              'Optional',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: AppColors.gold,
                              ),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                vendors.length > 1
                                    ? 'Scroll to see all ${vendors.length} options'
                                    : 'Select a preferred vendor for personalized service',
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  color: AppColors.textHint,
                                ),
                              ),
                              const SizedBox(height: 10),
                              SizedBox(
                                height: 112,
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: vendors.length + 1,
                                  separatorBuilder: (_, _) =>
                                      const SizedBox(width: 10),
                                  itemBuilder: (_, i) {
                                    if (i == 0) {
                                      final sel = _pvId == null;
                                      return _PvCard(
                                        label: 'No Preference',
                                        sublabel: 'Any available vendor',
                                        fee: null,
                                        isSelected: sel,
                                        onTap: () => setState(() {
                                          _pvId = null;
                                          _pvName = null;
                                          _pvFee = 0.0;
                                        }),
                                      );
                                    }
                                    final v = vendors[i - 1];
                                    final fee = v.instahelpPreferredVendorFee > 0
                                        ? v.instahelpPreferredVendorFee
                                        : v.preferredVendorFee;
                                    return _PvCard(
                                      label: v.businessName,
                                      sublabel: v.rating != null
                                          ? '★ ${v.rating!.toStringAsFixed(1)}'
                                          : null,
                                      fee: fee > 0
                                          ? '+₹${fee.toInt()}'
                                          : null,
                                      isSelected: _pvId == v.id,
                                      onTap: () => setState(() {
                                        _pvId = v.id;
                                        _pvName = v.businessName;
                                        _pvFee = fee;
                                      }),
                                      vendorId: v.id,
                                      dateStr: dateStr,
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    );
                  },
                ),

              // ── Price Summary ─────────────────────────────────────────────
              _SectionCard(
                title: 'Price Summary',
                child: !configLoaded
                    ? Row(
                        children: [
                          const SizedBox(
                            width: 13,
                            height: 13,
                            child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: AppColors.primary),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Calculating...',
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      )
                    : Column(
                        children: [
                          _SummaryRow(
                            label: 'Subtotal',
                            value: _fmt.format(basePrice),
                          ),
                          if (surgeAmt > 0)
                            _SummaryRow(
                              label: cfg.surgeFeeType == 'percentage'
                                  ? 'Surge Fee (${cfg.surgeFeeValue.toStringAsFixed(0)}%)'
                                  : 'Surge Fee',
                              value: _fmt.format(surgeAmt),
                            ),
                          if (scAmt > 0)
                            _SummaryRow(
                              label: cfg.serviceChargeType == 'percentage'
                                  ? 'Service Charge (${cfg.serviceChargeValue.toStringAsFixed(0)}%)'
                                  : 'Service Charge',
                              value: _fmt.format(scAmt),
                            ),
                          if (gstAmt > 0)
                            _SummaryRow(
                              label:
                                  'GST (${cfg.gstPercent.toStringAsFixed(cfg.gstPercent % 1 == 0 ? 0 : 1)}%)',
                              value: _fmt.format(gstAmt),
                            ),
                          if (_pvFee > 0)
                            _SummaryRow(
                              label:
                                  'Preferred Vendor Fee${_pvName != null ? ' ($_pvName)' : ''}',
                              value: _fmt.format(_pvFee),
                            ),
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 10),
                            child: Divider(height: 1),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Total',
                                style: GoogleFonts.poppins(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                _fmt.format(totalPrice),
                                style: GoogleFonts.poppins(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.primary,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),

        // ── Error banner ────────────────────────────────────────────────────
        if (_error != null)
          Container(
            width: double.infinity,
            color: AppColors.error.withValues(alpha: 0.08),
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.error_outline_rounded,
                    size: 16, color: AppColors.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _error!,
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.error),
                  ),
                ),
              ],
            ),
          ),

        // ── Bottom bar ──────────────────────────────────────────────────────
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _fmt.format(totalPrice),
                    style: GoogleFonts.poppins(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                    ),
                  ),
                  Text(
                    'incl. taxes & fees',
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: FilledButton(
                  onPressed: _placing
                      ? null
                      : () => _placeBooking(financialConfig),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _placing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : Text(
                          'Place Booking',
                          style: GoogleFonts.poppins(
                              fontSize: 15, fontWeight: FontWeight.w700),
                        ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Read-only display row ─────────────────────────────────────────────────────

class _ReadOnlyRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _ReadOnlyRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.primary),
        const SizedBox(width: 10),
        Text(
          text,
          style: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.primaryLight,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            'Set',
            style: GoogleFonts.poppins(
              fontSize: 10,
              color: AppColors.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Summary row ───────────────────────────────────────────────────────────────

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  const _SummaryRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
            Text(
              value,
              style: GoogleFonts.poppins(
                fontSize: 13,
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
}

// ── Price row ─────────────────────────────────────────────────────────────────

class _PriceRow extends StatelessWidget {
  final String label;
  final double amount;
  final NumberFormat fmt;
  final bool primary;
  const _PriceRow({
    required this.label,
    required this.amount,
    required this.fmt,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: primary
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
                fontWeight:
                    primary ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
            Text(
              fmt.format(amount),
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: primary
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
                fontWeight:
                    primary ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      );
}

// ── Preferred vendor card (InstaHelp checkout) ────────────────────────────────

class _PvCard extends ConsumerWidget {
  final String label;
  final String? sublabel;
  final String? fee;
  final bool isSelected;
  final VoidCallback onTap;
  final String? vendorId;
  final String? dateStr;

  const _PvCard({
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.sublabel,
    this.fee,
    this.vendorId,
    this.dateStr,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    bool? isBusyValue;
    if (vendorId != null && dateStr != null) {
      isBusyValue = ref
          .watch(vendorBusyProvider((vendorId: vendorId!, date: dateStr!)))
          .valueOrNull;
    }
    final isBusy = isBusyValue ?? false;
    final effectiveSel = isSelected && !isBusy;

    return GestureDetector(
      onTap: isBusy ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 150,
        decoration: BoxDecoration(
          color: effectiveSel ? AppColors.goldLight : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: effectiveSel ? AppColors.gold : AppColors.border,
            width: effectiveSel ? 1.5 : 1.0,
          ),
        ),
        padding: const EdgeInsets.all(11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: effectiveSel
                          ? AppColors.primary
                          : AppColors.textPrimary,
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color:
                        effectiveSel ? AppColors.gold : Colors.transparent,
                    border: Border.all(
                      color: effectiveSel
                          ? AppColors.gold
                          : AppColors.border,
                      width: 1.5,
                    ),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: effectiveSel
                      ? const Icon(Icons.check_rounded,
                          size: 11, color: Colors.white)
                      : const Icon(Icons.add_rounded,
                          size: 11, color: AppColors.textHint),
                ),
              ],
            ),
            if (sublabel != null) ...[
              const SizedBox(height: 2),
              Text(
                sublabel!,
                style: GoogleFonts.poppins(
                  fontSize: 10,
                  color: AppColors.textHint,
                ),
              ),
            ],
            const Spacer(),
            if (fee != null)
              Text(
                fee!,
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color:
                      effectiveSel ? AppColors.gold : AppColors.textPrimary,
                ),
              ),
            if (vendorId != null && dateStr != null && isBusyValue != null) ...[
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: isBusy ? AppColors.error : AppColors.success,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 3),
                  Flexible(
                    child: Text(
                      isBusy ? 'Busy' : 'Available',
                      style: TextStyle(
                        fontSize: 9,
                        color: isBusy ? AppColors.error : AppColors.success,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Section card ──────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? trailing;

  const _SectionCard({
    required this.title,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                ),
              ),
              if (trailing != null) ...[
                const Spacer(),
                trailing!,
              ],
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

