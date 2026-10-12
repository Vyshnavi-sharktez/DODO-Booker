import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../auth/application/providers/auth_provider.dart';
import '../../../catalog_v2/application/providers/catalog_node_providers.dart';
import '../../../catalog_v2/domain/models/catalog_node.dart';
import '../../../coupons/application/providers/coupons_providers.dart';
import '../../../coupons/domain/models/coupon.dart';
import '../../../service_addons/application/providers/service_addons_providers.dart';
import '../../../service_addons/domain/models/service_addon.dart';
import '../../../tax_settings/data/tax_settings_repository.dart';
import '../../../dodo_teams/application/providers/dodo_teams_providers.dart';
import '../../../vendors/application/providers/vendors_providers.dart';
import '../../../vendors/presentation/widgets/vendor_location_picker_dialog.dart';
import '../../application/providers/bookings_providers.dart';
import 'booking_assignment_dialog.dart';
import '../../data/admin_slot_service.dart';
import '../../domain/models/booking.dart';
import 'admin_coupon_browser_dialog.dart';
import '../../domain/models/booking_addon.dart';
import '../../domain/models/booking_item.dart';

final _dateFmt = DateFormat('dd MMM yyyy');
final _priceFmtEdit = NumberFormat.currency(symbol: '₹', decimalDigits: 0);

final _editTaxSettingsFutureProvider =
    FutureProvider.autoDispose<TaxSettingsConfig>((ref) {
  return TaxSettingsRepository(ref.watch(supabaseClientProvider)).fetch();
});

const _editStatusOptions = [
  ('pending',              'Pending'),
  ('assigned',             'Assigned'),
  ('assigned_to_dodo_team','Assigned to DODO Team'),
  ('no_vendor_accepted',   'No Vendor Accepted'),
  ('accepted',             'Accepted'),
  ('on_the_way',           'On The Way'),
  ('arrived',              'Arrived'),
  ('in_progress',          'In Progress'),
  ('completed',            'Completed'),
  ('rejected',             'Rejected'),
  ('cancelled',            'Cancelled'),
];

// ── Dialog ────────────────────────────────────────────────────────────────────

class BookingEditDialog extends ConsumerStatefulWidget {
  final Booking booking;
  final VoidCallback? onAssignRequested;

  const BookingEditDialog({
    super.key,
    required this.booking,
    this.onAssignRequested,
  });

  @override
  ConsumerState<BookingEditDialog> createState() => _BookingEditDialogState();
}

class _BookingEditDialogState extends ConsumerState<BookingEditDialog> {
  final _formKey = GlobalKey<FormState>();
  final _addressCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _couponCtrl = TextEditingController();

  // Catalog item rows (pre-populated from existing booking.items)
  late final List<GlobalKey<_EditItemRowState>> _itemKeys;
  // Custom item rows (pre-populated from items without serviceId)
  late final List<_CustomItemData> _customItems;

  late String _status;
  DateTime? _serviceDate;
  String? _scheduledTime;
  double? _latitude;
  double? _longitude;

  // Assignment display state — updated after a successful Change Assignment.
  late String _assignmentType;
  late String _assignedVendorId;
  late String _assignedDodoTeamId;

  // Slot state
  String? _slotServiceId; // service driving slot loading
  Future<List<String>>? _slotsFuture;
  bool _slotWasUnavailable = false;
  bool _slotsInitialized = false;

  // Coupon
  Coupon? _appliedCoupon;
  String? _couponError;
  bool _couponApplied = false;

  bool _saving = false;
  bool _submitted = false;
  AutovalidateMode _autovalidateMode = AutovalidateMode.disabled;

  @override
  void initState() {
    super.initState();
    final b = widget.booking;

    _addressCtrl.text = b.address ?? '';
    _notesCtrl.text = b.notes ?? '';
    _couponCtrl.text = b.couponCode ?? '';
    _status = b.status;
    _serviceDate = b.serviceDate;
    _scheduledTime = b.scheduledTime;
    _latitude = b.latitude;
    _longitude = b.longitude;
    _assignmentType = b.assignmentType;
    _assignedVendorId = b.vendorId;
    _assignedDodoTeamId = b.dodoTeamId;

    // Pre-seed _slotServiceId from the booking's first catalog item so that
    // when _EditItemRow's async addon-fetch completes and calls _onItemChanged,
    // the service-ID equality check is false and _serviceDate is not cleared.
    final firstCatalogItem =
        b.items.where((i) => i.serviceId.isNotEmpty).firstOrNull;
    if (firstCatalogItem != null) {
      _slotServiceId = firstCatalogItem.serviceId;
    }

    // Build item keys for catalog items
    final catalogItems = b.items.where((i) => i.serviceId.isNotEmpty).toList();
    _itemKeys = List.generate(
      catalogItems.isEmpty ? 1 : catalogItems.length,
      (_) => GlobalKey<_EditItemRowState>(),
    );

    // Build custom items from items without serviceId
    _customItems = b.items
        .where((i) => i.serviceId.isEmpty)
        .map((i) => _CustomItemData(
              categoryName: i.categoryName,
              name: i.displayName,
              price: i.unitPrice,
              quantity: i.quantity,
            ))
        .toList();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_slotsInitialized && _slotServiceId != null && _serviceDate != null) {
      _slotsInitialized = true;
      _startLoadSlots(_slotServiceId!, _serviceDate!);
    }
  }

  @override
  void dispose() {
    _addressCtrl.dispose();
    _notesCtrl.dispose();
    _couponCtrl.dispose();
    super.dispose();
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  List<BookingItem> get _catalogItems =>
      widget.booking.items.where((i) => i.serviceId.isNotEmpty).toList();

  List<BookingAddon> get _existingAddons => widget.booking.addons;
  Set<String> get _existingAddonIds =>
      _existingAddons.map((a) => a.addonId).toSet();

  String? _firstServiceId() {
    if (_itemKeys.isEmpty) return null;
    return _itemKeys[0].currentState?.currentServiceId;
  }

  void _onItemChanged() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkAndHandleDuplicate());
    final newServiceId = _firstServiceId();
    setState(() {
      if (newServiceId != _slotServiceId) {
        _slotServiceId = newServiceId;
        _serviceDate = null;
        _scheduledTime = null;
        _slotsFuture = null;
        _slotWasUnavailable = false;
      }
      _revalidateCoupon();
    });
  }

  void _checkAndHandleDuplicate() {
    if (!mounted) return;
    final seen = <String, int>{};
    for (int i = 0; i < _itemKeys.length; i++) {
      final svcId = _itemKeys[i].currentState?.currentServiceId;
      if (svcId != null && svcId.isNotEmpty) {
        if (seen.containsKey(svcId)) {
          _showAlreadyInCartDialog(firstIdx: seen[svcId]!, dupIdx: i);
          return;
        }
        seen[svcId] = i;
      }
    }
  }

  Future<void> _showAlreadyInCartDialog({
    required int firstIdx,
    required int dupIdx,
  }) async {
    final firstState = _itemKeys[firstIdx].currentState;
    final svcName = firstState?.currentServiceName ?? 'This service';
    final currentQty = firstState?.currentQuantity ?? 1;

    final newQty = await showDialog<int>(
      context: context,
      builder: (_) => _AlreadyInCartDialog(
        serviceName: svcName,
        currentQuantity: currentQty,
        itemNumber: firstIdx + 1,
      ),
    );

    if (!mounted) return;
    if (newQty != null) {
      _itemKeys[firstIdx].currentState?.setQuantity(newQty);
    }
    setState(() {
      if (dupIdx < _itemKeys.length) _itemKeys.removeAt(dupIdx);
    });
  }

  void _revalidateCoupon() {
    if (_appliedCoupon == null || !_couponApplied) return;
    if (_appliedCoupon!.applicabilityType != 'all' &&
        _appliedCoupon!.applicableNodeIds.isNotEmpty) {
      final ids = _collectCartNodeIds();
      if (!ids.any((id) => _appliedCoupon!.applicableNodeIds.contains(id))) {
        _appliedCoupon = null;
        _couponApplied = false;
        _couponError = 'Coupon removed — no eligible items remaining';
      }
    }
  }

  List<String> _collectCartNodeIds() {
    final ids = <String>{};
    for (final key in _itemKeys) {
      ids.addAll(key.currentState?.nodeIds ?? []);
    }
    return ids.toList();
  }

  double _computeSubtotal() {
    double total = 0.0;
    for (final key in _itemKeys) {
      final s = key.currentState;
      if (s != null) total += s.lineTotal + s.addonsTotal;
    }
    for (final ci in _customItems) {
      total += ci.price * ci.quantity;
    }
    return total;
  }

  double _computeDiscount(double subtotal, Coupon? coupon) {
    if (coupon == null) return 0.0;
    final eligible = coupon.applicabilityType == 'all' ||
            coupon.applicableNodeIds.isEmpty
        ? subtotal
        : () {
            double e = 0.0;
            for (final key in _itemKeys) {
              final s = key.currentState;
              if (s == null) continue;
              if (s.nodeIds.any((id) => coupon.applicableNodeIds.contains(id))) {
                e += s.lineTotal + s.addonsTotal;
              }
            }
            return e;
          }();
    double disc = coupon.discountType == 'percentage'
        ? eligible * coupon.discountValue / 100.0
        : coupon.discountValue;
    if (coupon.maxDiscountAmount != null && disc > coupon.maxDiscountAmount!) {
      disc = coupon.maxDiscountAmount!;
    }
    return disc.clamp(0.0, eligible);
  }

  // ── Assignment section ────────────────────────────────────────────────────────

  Future<void> _openChangeAssignment() async {
    final currentBookings =
        ref.read(bookingsNotifierProvider).valueOrNull ?? [];
    final currentBooking = currentBookings.firstWhere(
      (b) => b.id == widget.booking.id,
      orElse: () => widget.booking,
    );
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => BookingAssignmentDialog(
        booking: currentBooking,
        onSave: ({
          required assignmentType,
          vendorId,
          dodoTeamId,
          required serviceDate,
          notes,
        }) async {
          await ref
              .read(bookingsNotifierProvider.notifier)
              .updateBookingAssignment(
                widget.booking.id,
                assignmentType: assignmentType,
                vendorId: vendorId,
                dodoTeamId: dodoTeamId,
                serviceDate: serviceDate,
                notes: notes,
              );
          if (mounted) {
            setState(() {
              _assignmentType = assignmentType;
              _assignedVendorId = vendorId ?? '';
              _assignedDodoTeamId = dodoTeamId ?? '';
            });
          }
        },
      ),
    );
  }

  Widget _buildAssignmentSection({
    required List<dynamic> vendors,
    required List<dynamic> teams,
  }) {
    final vendor = vendors
        .where((v) => (v.id as String?) == _assignedVendorId)
        .firstOrNull;
    final team = teams
        .where((t) => (t.id as String?) == _assignedDodoTeamId)
        .firstOrNull;

    final isAssigned = _assignmentType == 'External Vendor' ||
        _assignmentType == 'DODO Team';

    final displayName = switch (_assignmentType) {
      'External Vendor' => (vendor?.businessName as String?) ??
          (widget.booking.vendorName.isNotEmpty
              ? widget.booking.vendorName
              : 'Unknown Vendor'),
      'DODO Team' => (team?.teamName as String?) ??
          (_assignedDodoTeamId.isNotEmpty
              ? _assignedDodoTeamId
              : 'DODO Team'),
      _ => 'Unassigned',
    };

    final badgeColor = switch (_assignmentType) {
      'External Vendor' => const Color(0xFF2563EB),
      'DODO Team' => const Color(0xFF6B46C1),
      _ => const Color(0xFFD97706),
    };
    final badgeBg = switch (_assignmentType) {
      'External Vendor' => const Color(0xFFDBEAFE),
      'DODO Team' => const Color(0xFFF3E8FF),
      _ => const Color(0xFFFEF3C7),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: badgeBg.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: badgeColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: badgeBg,
            child: Icon(
              _assignmentType == 'DODO Team'
                  ? Icons.groups_rounded
                  : Icons.person_rounded,
              color: badgeColor,
              size: 16,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isAssigned ? 'Assigned' : 'Unassigned',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: badgeColor,
                  ),
                ),
                if (isAssigned) ...[
                  Text(
                    displayName,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  Text(
                    _assignmentType,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (isAssigned)
            OutlinedButton.icon(
              onPressed: _saving ? null : _openChangeAssignment,
              icon: const Icon(Icons.swap_horiz_rounded, size: 14),
              label: const Text('Change Assignment'),
              style: OutlinedButton.styleFrom(
                foregroundColor: badgeColor,
                side: BorderSide(color: badgeColor),
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 6),
              ),
            ),
        ],
      ),
    );
  }

  // ── Date + slot ───────────────────────────────────────────────────────────────

  void _startLoadSlots(String svcId, DateTime date) {
    final future = AdminSlotService.fetchSlots(
      ref.read(supabaseClientProvider),
      svcId,
      date,
    );
    _slotsFuture = future;
    future.then((slots) {
      if (!mounted) return;
      setState(() {
        // Clear the existing time only when the slot list loaded successfully
        // (non-empty) and the existing slot is no longer in it. An empty result
        // may mean "no scheduling configured" or a transient error — preserve
        // the existing time so the admin is not blocked unnecessarily.
        if (slots.isNotEmpty &&
            _scheduledTime != null &&
            !slots.contains(_scheduledTime)) {
          _slotWasUnavailable = true;
          _scheduledTime = null;
        }
      });
    }).catchError((_) {});
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _serviceDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null && mounted) {
      final svcId = _firstServiceId() ?? '';
      setState(() {
        _serviceDate = picked;
        _scheduledTime = null;
        _slotWasUnavailable = false;
      });
      _startLoadSlots(svcId, picked);
    }
  }

  Widget _buildSlotPicker() {
    final hasService = (_firstServiceId() ?? '').isNotEmpty;
    final hasDate = _serviceDate != null;
    final slotError = _submitted && hasDate && _scheduledTime == null
        ? 'Please select a time slot'
        : null;

    if (!hasService || !hasDate || _slotsFuture == null) {
      return TextFormField(
        initialValue: _scheduledTime,
        onChanged: (v) =>
            setState(() => _scheduledTime = v.trim().isEmpty ? null : v.trim()),
        decoration: InputDecoration(
          labelText: 'Time Slot',
          hintText: hasService && hasDate
              ? 'e.g. 10:00 AM'
              : 'Select service & date first',
          prefixIcon: const Icon(Icons.access_time_rounded),
          isDense: true,
          errorText: slotError,
        ),
      );
    }

    return FutureBuilder<List<String>>(
      future: _slotsFuture,
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Time Slot',
              prefixIcon: Icon(Icons.access_time_rounded),
              isDense: true,
            ),
            child: const SizedBox(
              height: 14,
              child: LinearProgressIndicator(),
            ),
          );
        }

        final slots = snap.data ?? [];
        Widget picker;

        if (slots.isNotEmpty) {
          picker = DropdownButtonFormField<String>(
            key: ValueKey('editslot_${_serviceDate?.toIso8601String()}'),
            // ignore: deprecated_member_use
            value: slots.contains(_scheduledTime) ? _scheduledTime : null,
            hint: const Text('Select time slot'),
            decoration: InputDecoration(
              labelText: 'Time Slot',
              prefixIcon: const Icon(Icons.access_time_rounded),
              isDense: true,
              errorText: slotError,
            ),
            items: slots
                .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                .toList(),
            onChanged: (v) => setState(() {
              _scheduledTime = v;
              _slotWasUnavailable = false;
            }),
          );
        } else {
          picker = TextFormField(
            initialValue: _scheduledTime,
            onChanged: (v) => setState(() {
              _scheduledTime = v.trim().isEmpty ? null : v.trim();
              _slotWasUnavailable = false;
            }),
            decoration: InputDecoration(
              labelText: 'Time Slot',
              hintText: 'No slots configured — enter manually',
              prefixIcon: const Icon(Icons.access_time_rounded),
              isDense: true,
              errorText: slotError,
            ),
          );
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            picker,
            if (_slotWasUnavailable)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 12),
                child: Text(
                  'Previous time slot is no longer available. Please select a new one.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.orange[800],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  // ── Location picker ───────────────────────────────────────────────────────────

  Future<void> _pickLocation() async {
    final result = await showDialog<VendorLocationPickerResult>(
      context: context,
      builder: (_) => VendorLocationPickerDialog(
        initialLatitude: _latitude,
        initialLongitude: _longitude,
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _latitude = result.latitude;
        _longitude = result.longitude;
        if (_addressCtrl.text.trim().isEmpty) {
          _addressCtrl.text = result.address ?? result.city ?? '';
        }
      });
    }
  }

  // ── Coupon ────────────────────────────────────────────────────────────────────

  void _applyCoupon() {
    final code = _couponCtrl.text.trim().toUpperCase();
    if (code.isEmpty) return;
    final coupons = ref.read(couponsNotifierProvider).valueOrNull ?? [];
    final coupon =
        coupons.where((c) => c.code.toUpperCase() == code).firstOrNull;
    if (coupon == null) {
      setState(() {
        _couponError = 'Coupon "$code" not found';
        _appliedCoupon = null;
        _couponApplied = false;
      });
      return;
    }
    if (!coupon.isActive || coupon.isExpired || coupon.isUsageLimitReached) {
      setState(() {
        _couponError = coupon.isExpired
            ? 'Coupon expired'
            : coupon.isUsageLimitReached
                ? 'Usage limit reached'
                : 'Coupon inactive';
        _appliedCoupon = null;
        _couponApplied = false;
      });
      return;
    }
    setState(() {
      _appliedCoupon = coupon;
      _couponError = null;
      _couponApplied = true;
    });
  }

  void _removeCoupon() {
    setState(() {
      _appliedCoupon = null;
      _couponError = null;
      _couponApplied = false;
      _couponCtrl.clear();
    });
  }

  Future<void> _openCouponBrowser() async {
    final result = await showDialog<Coupon>(
      context: context,
      builder: (_) => AdminCouponBrowserDialog(
        subtotal: _computeSubtotal(),
        cartNodeIds: _collectCartNodeIds(),
        selectedCouponId: _appliedCoupon?.id,
      ),
    );
    if (result != null && mounted) {
      _couponCtrl.text = result.code;
      _applyCoupon();
    }
  }

  // ── Submit ────────────────────────────────────────────────────────────────────

  Future<void> _submit(TaxSettingsConfig tax) async {
    setState(() {
      _submitted = true;
      _autovalidateMode = AutovalidateMode.onUserInteraction;
    });
    if (!_formKey.currentState!.validate()) return;
    if (_serviceDate == null) return;
    if (_scheduledTime == null) return;

    final bookingItems = <({
      String serviceId,
      String? customName,
      String? customCategoryName,
      int quantity,
      double unitPrice,
    })>[];
    final allAddons =
        <({String addonId, String addonName, double addonPrice})>[];

    for (int i = 0; i < _itemKeys.length; i++) {
      final data = _itemKeys[i].currentState?.buildItemData();
      if (data == null) return;
      bookingItems.add((
        serviceId: data.serviceId,
        customName: null,
        customCategoryName: null,
        quantity: data.quantity,
        unitPrice: data.unitPrice,
      ));
      for (final addon in data.selectedAddons) {
        if (!allAddons.any((a) => a.addonId == addon.id)) {
          allAddons.add((
            addonId: addon.id,
            addonName: addon.name,
            addonPrice: addon.price,
          ));
        }
      }
    }

    for (final ci in _customItems) {
      if (ci.name.trim().isEmpty || ci.price <= 0) return;
      bookingItems.add((
        serviceId: '',
        customName: ci.name.trim(),
        customCategoryName: ci.categoryName.trim().isEmpty ? null : ci.categoryName.trim(),
        quantity: ci.quantity,
        unitPrice: ci.price,
      ));
    }

    final subtotal = _computeSubtotal();
    final discAmt = _computeDiscount(subtotal, _appliedCoupon);
    final taxable = subtotal - discAmt;
    final taxAmt = tax.isEnabled
        ? (tax.taxType == 'percentage'
            ? taxable * tax.taxValue / 100.0
            : tax.taxValue)
        : 0.0;

    setState(() => _saving = true);
    try {
      await ref.read(bookingsNotifierProvider.notifier).updateBookingFull(
            id: widget.booking.id,
            serviceDate: _serviceDate!,
            address: _addressCtrl.text.trim(),
            status: _status,
            notes: _notesCtrl.text.trim().isEmpty
                ? null
                : _notesCtrl.text.trim(),
            scheduledTime: _scheduledTime,
            latitude: _latitude,
            longitude: _longitude,
            items: bookingItems,
            addons: allAddons,
            discountAmount: discAmt,
            taxAmount: taxAmt,
            couponCode: _appliedCoupon?.code,
          );
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Booking #${widget.booking.bookingNumber} updated successfully'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final taxAsync = ref.watch(_editTaxSettingsFutureProvider);
    final tax = taxAsync.valueOrNull ?? TaxSettingsConfig.defaults();
    final vendors = ref.watch(vendorsNotifierProvider).valueOrNull ?? [];
    final teams = ref.watch(dodoTeamsNotifierProvider).valueOrNull ?? [];

    final subtotal = _computeSubtotal();
    final discAmt = _computeDiscount(subtotal, _appliedCoupon);
    final taxable = subtotal - discAmt;
    final taxAmt = tax.isEnabled
        ? (tax.taxType == 'percentage'
            ? taxable * tax.taxValue / 100.0
            : tax.taxValue)
        : 0.0;
    final total = (taxable + taxAmt).clamp(0.0, double.infinity);

    final catalogItems = _catalogItems;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header ──────────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 20),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.edit_rounded, color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Edit Booking #${widget.booking.bookingNumber}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed:
                        _saving ? null : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white70),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),

            // ── Form ────────────────────────────────────────────────────────
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  autovalidateMode: _autovalidateMode,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Booking Items ──────────────────────────────────────
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Booking Items *',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () => setState(
                                () => _itemKeys.add(GlobalKey<_EditItemRowState>())),
                            icon: const Icon(Icons.add_rounded, size: 18),
                            label: const Text('Add Service'),
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.primary,
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                          const SizedBox(width: 6),
                          TextButton.icon(
                            onPressed: () => setState(
                                () => _customItems.add(_CustomItemData())),
                            icon: const Icon(Icons.add_box_outlined, size: 18),
                            label: const Text('Add Custom'),
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.textSecondary,
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      for (var i = 0; i < _itemKeys.length; i++) ...[
                        if (i > 0) const SizedBox(height: 12),
                        _EditItemRow(
                          key: _itemKeys[i],
                          index: i,
                          canRemove:
                              _itemKeys.length > 1 || _customItems.isNotEmpty,
                          onRemove: () =>
                              setState(() => _itemKeys.removeAt(i)),
                          onChanged: _onItemChanged,
                          initServiceId: i < catalogItems.length
                              ? catalogItems[i].serviceId
                              : null,
                          initQuantity: i < catalogItems.length
                              ? catalogItems[i].quantity
                              : 1,
                          initAddonIds: _existingAddonIds,
                          showError: _submitted,
                        ),
                      ],
                      for (var i = 0; i < _customItems.length; i++) ...[
                        const SizedBox(height: 12),
                        _CustomItemEditRow(
                          index: _itemKeys.length + i,
                          data: _customItems[i],
                          onRemove: () =>
                              setState(() => _customItems.removeAt(i)),
                          onChanged: () => setState(() {}),
                        ),
                      ],
                      const SizedBox(height: 20),

                      // ── Address ────────────────────────────────────────────
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _addressCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Service Address',
                                prefixIcon:
                                    Icon(Icons.location_on_outlined),
                                isDense: true,
                              ),
                              textCapitalization:
                                  TextCapitalization.sentences,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Tooltip(
                            message: _latitude != null
                                ? 'Location set (${_latitude!.toStringAsFixed(4)}, ${_longitude!.toStringAsFixed(4)})'
                                : 'Pick on map',
                            child: InkWell(
                              onTap: _pickLocation,
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                margin: const EdgeInsets.only(top: 4),
                                padding: const EdgeInsets.all(9),
                                decoration: BoxDecoration(
                                  color: _latitude != null
                                      ? AppColors.primary
                                          .withValues(alpha: 0.1)
                                      : AppColors.surface,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: _latitude != null
                                        ? AppColors.primary
                                            .withValues(alpha: 0.4)
                                        : AppColors.border,
                                  ),
                                ),
                                child: Icon(
                                  Icons.map_outlined,
                                  size: 18,
                                  color: _latitude != null
                                      ? AppColors.primary
                                      : AppColors.textSecondary,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // ── Date + Slot ────────────────────────────────────────
                      Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: _pickDate,
                              borderRadius: BorderRadius.circular(8),
                              child: InputDecorator(
                                decoration: InputDecoration(
                                  labelText: 'Service Date *',
                                  prefixIcon:
                                      const Icon(Icons.calendar_today_rounded),
                                  isDense: true,
                                  errorText: _submitted && _serviceDate == null
                                      ? 'Please select a service date'
                                      : null,
                                ),
                                child: Text(
                                  _serviceDate != null
                                      ? _dateFmt.format(_serviceDate!)
                                      : 'Select date',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: _serviceDate != null
                                        ? AppColors.textPrimary
                                        : AppColors.textSecondary,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: _buildSlotPicker()),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // ── Status + Notes ─────────────────────────────────────
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              // ignore: deprecated_member_use
                              value: _status,
                              decoration: const InputDecoration(
                                labelText: 'Status *',
                                prefixIcon:
                                    Icon(Icons.flag_rounded),
                                isDense: true,
                              ),
                              items: _editStatusOptions
                                  .map((s) => DropdownMenuItem(
                                        value: s.$1,
                                        child: Text(s.$2),
                                      ))
                                  .toList(),
                              onChanged: (v) {
                                if (v == 'assigned' || v == 'assigned_to_dodo_team') {
                                  if (widget.onAssignRequested != null) {
                                    Navigator.of(context).pop();
                                    widget.onAssignRequested!();
                                  } else {
                                    // onAssignRequested not available — revert
                                    setState(() {});
                                  }
                                } else if (v != null) {
                                  setState(() => _status = v);
                                }
                              },
                              validator: (v) =>
                                  v == null ? 'Required' : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _notesCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Notes',
                                hintText: 'Optional',
                                prefixIcon: Icon(Icons.notes_rounded),
                                isDense: true,
                              ),
                              maxLines: 3,
                              textCapitalization:
                                  TextCapitalization.sentences,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // ── Assignment ─────────────────────────────────────────
                      _buildAssignmentSection(
                          vendors: vendors, teams: teams),
                      const SizedBox(height: 20),

                      // ── Coupon ─────────────────────────────────────────────
                      const Text(
                        'Coupon / Discount',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _couponCtrl,
                              enabled: !_couponApplied,
                              decoration: InputDecoration(
                                labelText: 'Coupon Code',
                                hintText: 'Enter code',
                                prefixIcon:
                                    const Icon(Icons.discount_outlined),
                                isDense: true,
                                suffixIcon: _couponApplied
                                    ? const Icon(Icons.check_circle_rounded,
                                        color: AppColors.success, size: 20)
                                    : null,
                                errorText: _couponError,
                              ),
                              textCapitalization:
                                  TextCapitalization.characters,
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                    RegExp(r'[A-Z0-9a-z_\-]')),
                                _UpperCaseFormatterEdit(),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (_couponApplied)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: OutlinedButton.icon(
                                onPressed: _removeCoupon,
                                icon: const Icon(Icons.close_rounded,
                                    size: 16),
                                label: const Text('Remove'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.error,
                                  side: const BorderSide(
                                      color: AppColors.error),
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 13),
                                ),
                              ),
                            )
                          else ...[
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: FilledButton(
                                onPressed: _applyCoupon,
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 13),
                                ),
                                child: const Text('Apply'),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: OutlinedButton.icon(
                                onPressed: _openCouponBrowser,
                                icon: const Icon(Icons.local_offer_rounded,
                                    size: 14),
                                label: const Text('Browse'),
                                style: OutlinedButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 13),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 20),

                      // ── Summary ────────────────────────────────────────────
                      _EditSummaryBox(
                        subtotal: subtotal,
                        discountAmount: discAmt,
                        couponCode: _appliedCoupon?.code,
                        taxLabel: tax.isEnabled
                            ? (tax.taxType == 'percentage'
                                ? '${tax.taxName} (${tax.taxValue.toInt()}%)'
                                : tax.taxName)
                            : null,
                        taxAmount: taxAmt,
                        total: total,
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ── Footer ──────────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed:
                        _saving ? null : () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                    ),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: _saving ? null : () => _submit(tax),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 28, vertical: 12),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Save Changes'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Edit Item Row ─────────────────────────────────────────────────────────────

class _EditItemRow extends ConsumerStatefulWidget {
  const _EditItemRow({
    super.key,
    required this.index,
    required this.canRemove,
    required this.onRemove,
    required this.onChanged,
    this.initServiceId,
    this.initQuantity = 1,
    this.initAddonIds = const {},
    this.showError = false,
  });

  final int index;
  final bool canRemove;
  final VoidCallback onRemove;
  final VoidCallback onChanged;
  final String? initServiceId;
  final int initQuantity;
  final Set<String> initAddonIds;
  final bool showError;

  @override
  ConsumerState<_EditItemRow> createState() => _EditItemRowState();
}

class _EditItemRowState extends ConsumerState<_EditItemRow> {
  CatalogNode? _category;
  CatalogNode? _subCat;
  CatalogNode? _service;
  int _quantity = 1;
  List<ServiceAddon> _nodeAddons = [];
  Set<String> _selectedAddonIds = {};
  bool _loadingAddons = false;
  bool _initialized = false;

  String? get currentServiceId => _service?.id;

  List<String> get nodeIds {
    if (_service == null) return const [];
    return [_service!.id, ..._service!.parentIds];
  }

  double get lineTotal => (_service?.basePrice ?? 0.0) * _quantity;

  double get addonsTotal => _nodeAddons
      .where((a) => _selectedAddonIds.contains(a.id))
      .fold(0.0, (s, a) => s + a.price);

  int get currentQuantity => _quantity;
  String? get currentServiceName => _service?.name;
  void setQuantity(int qty) => setState(() => _quantity = qty);

  ({
    String serviceId,
    int quantity,
    double unitPrice,
    List<ServiceAddon> selectedAddons,
  })? buildItemData() {
    if (_service == null) return null;
    return (
      serviceId: _service!.id,
      quantity: _quantity,
      unitPrice: _service!.basePrice ?? 0.0,
      selectedAddons:
          _nodeAddons.where((a) => _selectedAddonIds.contains(a.id)).toList(),
    );
  }

  @override
  void initState() {
    super.initState();
    _quantity = widget.initQuantity;
  }

  void _initialize(List<CatalogNode> allNodes) {
    if (_initialized || widget.initServiceId == null) {
      _initialized = true;
      return;
    }
    // Find by ID only — don't filter by isBookable. The service may have been
    // toggled non-bookable after this booking was created; we still need to
    // display and preserve the historical item.
    final svc = allNodes
        .where((n) => n.id == widget.initServiceId)
        .firstOrNull;
    if (svc == null) {
      _initialized = true;
      return;
    }
    final subCatId = svc.primaryParentId;
    final subCat = subCatId != null
        ? allNodes.where((n) => n.id == subCatId).firstOrNull
        : null;
    final catId = subCat?.primaryParentId;
    final cat =
        catId != null ? allNodes.where((n) => n.id == catId).firstOrNull : null;

    _initialized = true;
    _category = cat;
    _subCat = subCat;
    _service = svc;

    if (svc.id.isNotEmpty) _fetchAddons(svc.id, preSelectIds: widget.initAddonIds);
  }

  void _onCategoryChanged(CatalogNode? cat) {
    setState(() {
      _category = cat;
      _subCat = null;
      _service = null;
      _nodeAddons = [];
      _selectedAddonIds = {};
    });
    widget.onChanged();
  }

  void _onSubCatChanged(CatalogNode? sub) {
    setState(() {
      _subCat = sub;
      _service = null;
      _nodeAddons = [];
      _selectedAddonIds = {};
    });
    widget.onChanged();
  }

  void _onServiceChanged(CatalogNode? svc) {
    setState(() {
      _service = svc;
      _nodeAddons = [];
      _selectedAddonIds = {};
      _loadingAddons = svc != null;
    });
    widget.onChanged();
    if (svc != null) _fetchAddons(svc.id);
  }

  Future<void> _fetchAddons(String nodeId,
      {Set<String> preSelectIds = const {}}) async {
    try {
      final addons =
          await ref.read(serviceAddonsRepositoryProvider).fetchNodeAddons(nodeId);
      if (mounted) {
        setState(() {
          _nodeAddons = addons.where((a) => a.isActive).toList();
          _selectedAddonIds = preSelectIds.isNotEmpty
              ? _nodeAddons
                  .where((a) => preSelectIds.contains(a.id))
                  .map((a) => a.id)
                  .toSet()
              : {};
          _loadingAddons = false;
        });
        widget.onChanged();
      }
    } catch (_) {
      if (mounted) setState(() => _loadingAddons = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final allNodes = ref.watch(catalogNodeNotifierProvider).valueOrNull ?? [];

    if (!_initialized && allNodes.isNotEmpty) {
      _initialize(allNodes);
    }

    final categories = allNodes
        .where((n) => n.isRoot && n.isActive)
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    final resolvedCat = _category != null
        ? categories.where((n) => n.id == _category!.id).firstOrNull
        : null;

    final subCats = resolvedCat == null
        ? <CatalogNode>[]
        : allNodes
            .where((n) =>
                n.parentIds.contains(resolvedCat.id) &&
                n.isActive &&
                !n.isBookable)
            .toList()
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    final resolvedSubCat = _subCat != null
        ? subCats.where((n) => n.id == _subCat!.id).firstOrNull
        : null;

    final services = resolvedSubCat == null
        ? <CatalogNode>[]
        : allNodes
            .where((n) =>
                n.parentIds.contains(resolvedSubCat.id) &&
                // Always include the pre-selected service even if it was made
                // non-bookable after this booking was created.
                (n.isActive && n.isBookable || n.id == _service?.id))
            .toList()
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    final resolvedService = _service != null
        ? services.where((n) => n.id == _service!.id).firstOrNull
        : null;

    final price = resolvedService?.basePrice;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Item ${widget.index + 1}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const Spacer(),
              if (widget.canRemove)
                IconButton(
                  onPressed: widget.onRemove,
                  icon: const Icon(Icons.remove_circle_outline_rounded,
                      size: 18),
                  color: AppColors.error,
                  tooltip: 'Remove item',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _CatalogDropdownEdit(
                  key: ValueKey('cat_${_category?.id}_${widget.index}'),
                  label: 'Category',
                  hint: 'Select category',
                  nodes: categories,
                  selectedId: _category?.id,
                  enabled: allNodes.isNotEmpty,
                  onChanged: _onCategoryChanged,
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 18, left: 6, right: 6),
                child: Icon(Icons.chevron_right_rounded,
                    size: 16, color: AppColors.textSecondary),
              ),
              Expanded(
                child: _CatalogDropdownEdit(
                  key: ValueKey('sub_${_subCat?.id}_${widget.index}'),
                  label: 'Sub Category',
                  hint: 'Select sub category',
                  nodes: subCats,
                  selectedId: _subCat?.id,
                  enabled: _category != null && subCats.isNotEmpty,
                  onChanged: _onSubCatChanged,
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 18, left: 6, right: 6),
                child: Icon(Icons.chevron_right_rounded,
                    size: 16, color: AppColors.textSecondary),
              ),
              Expanded(
                child: _CatalogDropdownEdit(
                  key: ValueKey('svc_${_service?.id}_${widget.index}'),
                  label: 'Service / Product',
                  hint: 'Select service',
                  nodes: services,
                  selectedId: _service?.id,
                  enabled: _subCat != null && services.isNotEmpty,
                  onChanged: _onServiceChanged,
                ),
              ),
            ],
          ),
          if (widget.showError && _service == null) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Text(
                'Please select a service',
                style: TextStyle(fontSize: 12, color: AppColors.error),
              ),
            ),
          ],
          if (resolvedService != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _InfoBoxEdit(
                    label: 'Unit Price',
                    value: price != null ? _priceFmtEdit.format(price) : '—',
                    valueColor: AppColors.textPrimary,
                    bgColor: AppColors.surface,
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Qty',
                          style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary)),
                      const SizedBox(width: 8),
                      _QtyButtonEdit(
                        icon: Icons.remove_rounded,
                        onTap: _quantity > 1
                            ? () {
                                setState(() => _quantity--);
                                widget.onChanged();
                              }
                            : null,
                      ),
                      Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 10),
                        child: Text('$_quantity',
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700)),
                      ),
                      _QtyButtonEdit(
                        icon: Icons.add_rounded,
                        onTap: () {
                          setState(() => _quantity++);
                          widget.onChanged();
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _InfoBoxEdit(
                    label: 'Line Total',
                    value: price != null
                        ? _priceFmtEdit.format(price * _quantity)
                        : '—',
                    valueColor: AppColors.primary,
                    bgColor: AppColors.primary.withValues(alpha: 0.06),
                    borderColor:
                        AppColors.primary.withValues(alpha: 0.2),
                  ),
                ),
              ],
            ),
            if (_loadingAddons)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Center(
                  child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                ),
              )
            else if (_nodeAddons.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: _nodeAddons.map((addon) {
                  final selected = _selectedAddonIds.contains(addon.id);
                  return FilterChip(
                    label: Text(
                        '${addon.name} (+${_priceFmtEdit.format(addon.price)})'),
                    selected: selected,
                    onSelected: (val) {
                      setState(() {
                        if (val) {
                          _selectedAddonIds.add(addon.id);
                        } else {
                          _selectedAddonIds.remove(addon.id);
                        }
                      });
                      widget.onChanged();
                    },
                    labelStyle:
                        const TextStyle(fontSize: 12),
                    visualDensity: VisualDensity.compact,
                  );
                }).toList(),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

// ── Custom item row ───────────────────────────────────────────────────────────

class _CustomItemData {
  String categoryName;
  String name;
  double price;
  int quantity;

  _CustomItemData({this.categoryName = '', this.name = '', this.price = 0.0, this.quantity = 1});
}

class _CustomItemEditRow extends StatelessWidget {
  const _CustomItemEditRow({
    required this.index,
    required this.data,
    required this.onRemove,
    required this.onChanged,
  });

  final int index;
  final _CustomItemData data;
  final VoidCallback onRemove;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.textSecondary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Custom Item ${index + 1}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: onRemove,
                icon: const Icon(Icons.remove_circle_outline_rounded,
                    size: 18),
                color: AppColors.error,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            initialValue: data.categoryName,
            onChanged: (v) {
              data.categoryName = v;
              onChanged();
            },
            decoration: const InputDecoration(
              labelText: 'Category Name (optional)',
              hintText: 'e.g. Home Cleaning',
              isDense: true,
            ),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: TextFormField(
                  initialValue: data.name,
                  onChanged: (v) {
                    data.name = v;
                    onChanged();
                  },
                  decoration: const InputDecoration(
                    labelText: 'Product Name *',
                    isDense: true,
                  ),
                  textCapitalization: TextCapitalization.sentences,
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Product name required'
                      : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  initialValue:
                      data.price > 0 ? data.price.toStringAsFixed(0) : '',
                  onChanged: (v) {
                    data.price = double.tryParse(v) ?? 0.0;
                    onChanged();
                  },
                  decoration: const InputDecoration(
                    labelText: 'Price (₹) *',
                    isDense: true,
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))
                  ],
                  validator: (v) {
                    final p = double.tryParse(v ?? '');
                    return (p == null || p <= 0) ? 'Valid price required' : null;
                  },
                ),
              ),
              const SizedBox(width: 10),
              Container(
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Qty',
                        style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary)),
                    const SizedBox(width: 8),
                    _QtyButtonEdit(
                      icon: Icons.remove_rounded,
                      onTap: data.quantity > 1
                          ? () {
                              data.quantity--;
                              onChanged();
                            }
                          : null,
                    ),
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 10),
                      child: Text('${data.quantity}',
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700)),
                    ),
                    _QtyButtonEdit(
                      icon: Icons.add_rounded,
                      onTap: () {
                        data.quantity++;
                        onChanged();
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Catalog dropdown ──────────────────────────────────────────────────────────

class _CatalogDropdownEdit extends StatelessWidget {
  const _CatalogDropdownEdit({
    super.key,
    required this.label,
    required this.hint,
    required this.nodes,
    required this.selectedId,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final String hint;
  final List<CatalogNode> nodes;
  final String? selectedId;
  final bool enabled;
  final void Function(CatalogNode?) onChanged;

  @override
  Widget build(BuildContext context) {
    final validId =
        nodes.any((n) => n.id == selectedId) ? selectedId : null;
    return DropdownButtonFormField<String>(
      key: ValueKey('${label}_$validId'),
      // ignore: deprecated_member_use
      value: validId,
      hint: Text(hint,
          style: const TextStyle(
              fontSize: 13, color: AppColors.textSecondary)),
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        enabled: enabled,
      ),
      items: nodes
          .map((n) => DropdownMenuItem(
                value: n.id,
                child: Text(n.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13)),
              ))
          .toList(),
      onChanged: enabled
          ? (id) => onChanged(
              id != null ? nodes.where((n) => n.id == id).firstOrNull : null)
          : null,
    );
  }
}

// ── Summary box ───────────────────────────────────────────────────────────────

class _EditSummaryBox extends StatelessWidget {
  const _EditSummaryBox({
    required this.subtotal,
    required this.discountAmount,
    required this.couponCode,
    required this.taxLabel,
    required this.taxAmount,
    required this.total,
  });

  final double subtotal;
  final double discountAmount;
  final String? couponCode;
  final String? taxLabel;
  final double taxAmount;
  final double total;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _EditSummaryRow(
              label: 'Subtotal',
              value: _priceFmtEdit.format(subtotal)),
          if (discountAmount > 0) ...[
            const SizedBox(height: 6),
            _EditSummaryRow(
              label: couponCode != null
                  ? 'Discount ($couponCode)'
                  : 'Discount',
              value: '−${_priceFmtEdit.format(discountAmount)}',
              valueColor: AppColors.success,
            ),
          ],
          if (taxLabel != null) ...[
            const SizedBox(height: 6),
            _EditSummaryRow(
                label: taxLabel!, value: _priceFmtEdit.format(taxAmount)),
          ],
          const SizedBox(height: 10),
          const Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 10),
          _EditSummaryRow(
            label: 'Total',
            value: _priceFmtEdit.format(total),
            labelBold: true,
            valueBold: true,
            valueColor: AppColors.primary,
          ),
        ],
      ),
    );
  }
}

class _EditSummaryRow extends StatelessWidget {
  const _EditSummaryRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.labelBold = false,
    this.valueBold = false,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final bool labelBold;
  final bool valueBold;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(label,
              style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  fontWeight:
                      labelBold ? FontWeight.w700 : FontWeight.w400)),
        ),
        Text(value,
            style: TextStyle(
                fontSize: valueBold ? 15 : 13,
                fontWeight:
                    valueBold ? FontWeight.w700 : FontWeight.w500,
                color: valueColor ?? AppColors.textPrimary)),
      ],
    );
  }
}

// ── Info box ──────────────────────────────────────────────────────────────────

class _InfoBoxEdit extends StatelessWidget {
  const _InfoBoxEdit({
    required this.label,
    required this.value,
    required this.valueColor,
    required this.bgColor,
    this.borderColor,
  });

  final String label;
  final String value;
  final Color valueColor;
  final Color bgColor;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor ?? AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 11, color: AppColors.textSecondary)),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: valueColor)),
        ],
      ),
    );
  }
}

// ── Qty button ────────────────────────────────────────────────────────────────

class _QtyButtonEdit extends StatelessWidget {
  const _QtyButtonEdit({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        width: 22,
        height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: onTap != null
              ? AppColors.primary.withValues(alpha: 0.1)
              : AppColors.border,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(icon,
            size: 14,
            color: onTap != null
                ? AppColors.primary
                : AppColors.textSecondary),
      ),
    );
  }
}

// ── Already-in-cart dialog ────────────────────────────────────────────────────

class _AlreadyInCartDialog extends StatefulWidget {
  const _AlreadyInCartDialog({
    required this.serviceName,
    required this.currentQuantity,
    required this.itemNumber,
  });

  final String serviceName;
  final int currentQuantity;
  final int itemNumber;

  @override
  State<_AlreadyInCartDialog> createState() => _AlreadyInCartDialogState();
}

class _AlreadyInCartDialogState extends State<_AlreadyInCartDialog> {
  late int _qty;

  @override
  void initState() {
    super.initState();
    _qty = widget.currentQuantity;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Row(
        children: [
          const Icon(Icons.shopping_cart_rounded,
              color: AppColors.primary, size: 20),
          const SizedBox(width: 8),
          const Text(
            'Already in Cart',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              style: const TextStyle(
                  fontSize: 14, color: AppColors.textSecondary, height: 1.5),
              children: [
                TextSpan(
                  text: '"${widget.serviceName}"',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                TextSpan(text: ' is already in Item ${widget.itemNumber}.'),
              ],
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Update the quantity below if needed.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _CartQtyBtn(
                icon: Icons.remove_rounded,
                enabled: _qty > 1,
                onTap: () => setState(() => _qty--),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Text(
                  '$_qty',
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              _CartQtyBtn(
                icon: Icons.add_rounded,
                enabled: true,
                onTap: () => setState(() => _qty++),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_qty),
          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
          child: const Text('Update'),
        ),
      ],
    );
  }
}

class _CartQtyBtn extends StatelessWidget {
  const _CartQtyBtn({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: enabled
              ? AppColors.primary.withValues(alpha: 0.1)
              : AppColors.border,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          size: 18,
          color: enabled ? AppColors.primary : AppColors.textSecondary,
        ),
      ),
    );
  }
}

// ── Upper-case formatter ──────────────────────────────────────────────────────

class _UpperCaseFormatterEdit extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
          TextEditingValue oldValue, TextEditingValue newValue) =>
      newValue.copyWith(text: newValue.text.toUpperCase());
}
