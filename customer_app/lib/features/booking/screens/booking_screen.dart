import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../models/service_model.dart';
import '../../../models/address_model.dart';
import '../../../models/time_slot_model.dart';
import '../../../models/booking_model.dart';
import '../services/booking_providers.dart';
import '../widgets/booking_stepper.dart';
import 'select_address_screen.dart';
import 'select_datetime_screen.dart';
import 'booking_summary_screen.dart';
import 'booking_success_screen.dart';

class BookingScreen extends ConsumerStatefulWidget {
  final ServiceModel service;

  const BookingScreen({super.key, required this.service});

  @override
  ConsumerState<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends ConsumerState<BookingScreen> {
  int _step = 0;
  AddressModel? _address;
  DateTime _date = DateTime.now();
  TimeSlotModel? _slot;
  BookingModel? _booking;
  bool _isCreating = false;
  String? _errorMessage;

  bool get _canContinue {
    if (_step == 0) return _address != null;
    if (_step == 1) return _slot != null;
    return true;
  }

  String get _buttonLabel => _step == 2 ? 'Confirm Booking' : 'Continue';

  Future<void> _onNext() async {
    if (_step < 2) {
      setState(() => _step++);
      return;
    }
    // Step 2: confirm booking
    setState(() {
      _isCreating = true;
      _errorMessage = null;
    });
    try {
      final booking = await ref.read(bookingServiceProvider).createBooking(
            service: widget.service,
            address: _address!,
            date: _date,
            slot: _slot!,
          );
      if (!mounted) return;
      setState(() {
        _booking = booking;
        _isCreating = false;
        _step = 3;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isCreating = false;
        _errorMessage = 'Failed to confirm booking. Please try again.';
      });
    }
  }

  void _onBack() {
    if (_step == 0) {
      Navigator.of(context).pop();
    } else {
      setState(() => _step--);
    }
  }

  Widget _buildStepContent() {
    switch (_step) {
      case 0:
        return SelectAddressScreen(
          selectedAddress: _address,
          onAddressSelected: (addr) => setState(() => _address = addr),
        );
      case 1:
        return SelectDatetimeScreen(
          selectedDate: _date,
          selectedSlot: _slot,
          onDateChanged: (date) => setState(() {
            _date = date;
            _slot = null;
          }),
          onSlotSelected: (slot) => setState(() => _slot = slot),
        );
      case 2:
        return BookingSummaryScreen(
          service: widget.service,
          address: _address!,
          date: _date,
          slot: _slot!,
        );
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Success screen takes over the entire scaffold
    if (_step == 3 && _booking != null) {
      return BookingSuccessScreen(
        booking: _booking!,
        onViewBookings: () => context.go('/'),
        onBackToHome: () => context.go('/'),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(widget.service.name, overflow: TextOverflow.ellipsis),
        leading: BackButton(onPressed: _onBack),
      ),
      body: Column(
        children: [
          // Stepper
          Container(
            color: AppColors.surface,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: BookingStepper(currentStep: _step),
          ),
          const Divider(height: 1),

          // Step content
          Expanded(child: _buildStepContent()),

          // Error banner
          if (_errorMessage != null)
            Container(
              width: double.infinity,
              color: AppColors.error.withAlpha(15),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded, size: 16, color: AppColors.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(fontSize: 13, color: AppColors.error),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      bottomNavigationBar: _BottomBar(
        label: _buttonLabel,
        enabled: _canContinue && !_isCreating,
        isLoading: _isCreating,
        onPressed: _canContinue ? _onNext : null,
      ),
    );
  }
}

// ── Bottom action bar ─────────────────────────────────────────────────────────

class _BottomBar extends StatelessWidget {
  final String label;
  final bool enabled;
  final bool isLoading;
  final VoidCallback? onPressed;

  const _BottomBar({
    required this.label,
    required this.enabled,
    required this.isLoading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        12 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(18),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: FilledButton(
        onPressed: enabled ? onPressed : null,
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        child: isLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            : Text(
                label,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
      ),
    );
  }
}
