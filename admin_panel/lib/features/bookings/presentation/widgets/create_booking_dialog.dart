import 'dart:async';

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
import '../../../vendors/presentation/widgets/vendor_location_picker_dialog.dart';
import '../../data/admin_slot_service.dart';
import 'admin_coupon_browser_dialog.dart';

final _dateFmt = DateFormat('dd MMM yyyy');
final _priceFmt = NumberFormat.currency(symbol: '₹', decimalDigits: 0);

final _taxSettingsFutureProvider =
    FutureProvider.autoDispose<TaxSettingsConfig>((ref) {
  return TaxSettingsRepository(ref.watch(supabaseClientProvider)).fetch();
});

// -- Dialog widget -------------------------------------------------------------

class CreateBookingDialog extends ConsumerStatefulWidget {
  const CreateBookingDialog({
    super.key,
    required this.onCreate,
  });

  final Future<void> Function({
    required String customerId,
    required DateTime serviceDate,
    required String address,
    String? notes,
    String? scheduledTime,
    double? latitude,
    double? longitude,
    required List<({
      String serviceId,
      String? customName,
      String? customCategoryName,
      int quantity,
      double unitPrice,
    })> items,
    required List<({
      String addonId,
      String addonName,
      double addonPrice,
    })> addons,
    double discountAmount,
    double taxAmount,
    String? couponCode,
  }) onCreate;

  @override
  ConsumerState<CreateBookingDialog> createState() =>
      _CreateBookingDialogState();
}

class _CreateBookingDialogState extends ConsumerState<CreateBookingDialog> {
  final _formKey = GlobalKey<FormState>();
  final _customerSearchCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _couponCtrl = TextEditingController();

  // Customer search state
  _CustomerResult? _selectedCustomer;
  List<_CustomerResult> _customerSearchResults = [];
  bool _customerSearching = false;
  Timer? _customerSearchDebounce;

  DateTime? _serviceDate;
  bool _creating = false;

  double? _latitude;
  double? _longitude;

  // Catalog item keys
  final List<GlobalKey<_BookingItemRowState>> _itemKeys = [
    GlobalKey<_BookingItemRowState>(),
  ];

  // Custom item keys
  final List<GlobalKey<_CustomItemRowState>> _customItemKeys = [];

  // Time slot + service-aware slot loading
  String? _scheduledTime;
  String? _primaryServiceId;
  Future<List<String>>? _slotsFuture;

  // Coupon state
  Coupon? _appliedCoupon;
  String? _couponError;
  bool _couponApplied = false;

  @override
  void dispose() {
    _customerSearchDebounce?.cancel();
    _customerSearchCtrl.dispose();
    _addressCtrl.dispose();
    _notesCtrl.dispose();
    _couponCtrl.dispose();
    super.dispose();
  }

  // ── Customer search ──────────────────────────────────────────────────────────

  void _onCustomerSearchChanged(String q) {
    _customerSearchDebounce?.cancel();
    final query = q.trim();
    if (query.length < 2) {
      if (_customerSearchResults.isNotEmpty) {
        setState(() => _customerSearchResults = []);
      }
      return;
    }
    _customerSearchDebounce = Timer(
      const Duration(milliseconds: 300),
      () => _searchCustomers(query),
    );
  }

  Future<void> _searchCustomers(String q) async {
    setState(() => _customerSearching = true);
    try {
      final client = ref.read(supabaseClientProvider);
      final rows = await client
          .from('customers')
          .select('id, full_name, phone, email')
          .or('full_name.ilike.%$q%,phone.ilike.%$q%,email.ilike.%$q%')
          .limit(6);
      if (mounted) {
        setState(() {
          _customerSearchResults = (rows as List<dynamic>).map((r) {
            final m = r as Map<String, dynamic>;
            return _CustomerResult(
              id: m['id'] as String,
              name: (m['full_name'] as String?) ?? '—',
              phone: (m['phone'] as String?) ?? '—',
              email: m['email'] as String?,
            );
          }).toList();
          _customerSearching = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _customerSearching = false);
    }
  }

  void _addItem() {
    setState(() => _itemKeys.add(GlobalKey<_BookingItemRowState>()));
  }

  void _removeItem(int index) {
    if (_itemKeys.length <= 1 && _customItemKeys.isEmpty) return;
    setState(() => _itemKeys.removeAt(index));
  }

  void _addCustomItem() {
    setState(() => _customItemKeys.add(GlobalKey<_CustomItemRowState>()));
  }

  void _removeCustomItem(int index) {
    setState(() => _customItemKeys.removeAt(index));
  }

  // Returns the union of node IDs (service + ancestors) for all selected items.
  List<String> _collectCartNodeIds() {
    final ids = <String>{};
    for (final key in _itemKeys) {
      ids.addAll(key.currentState?.nodeIds ?? []);
    }
    return ids.toList();
  }

  // Subtotal restricted to items eligible for [coupon].
  // Returns full subtotal for 'all' coupons; restricted subtotal otherwise.
  double _computeEligibleSubtotal(Coupon coupon) {
    if (coupon.applicabilityType == 'all' || coupon.applicableNodeIds.isEmpty) {
      return _computeSubtotal();
    }
    double eligible = 0.0;
    for (final key in _itemKeys) {
      final s = key.currentState;
      if (s == null) continue;
      final matches =
          s.nodeIds.any((id) => coupon.applicableNodeIds.contains(id));
      if (matches) eligible += s.lineTotal + s.addonsTotal;
    }
    // Custom items have no catalog node - never eligible for restricted coupons.
    return eligible;
  }

  void _onItemChanged() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkAndHandleDuplicate());
    setState(() {
      // Service-first: if the primary service changes, clear date + slot.
      final newServiceId = _itemKeys.isEmpty
          ? null
          : _itemKeys[0].currentState?.currentServiceId;
      if (newServiceId != _primaryServiceId) {
        _primaryServiceId = newServiceId;
        _serviceDate = null;
        _scheduledTime = null;
        _slotsFuture = null;
      }

      // Auto-remove a restricted coupon if no eligible items remain.
      if (_appliedCoupon != null &&
          _couponApplied &&
          _appliedCoupon!.applicabilityType != 'all' &&
          _appliedCoupon!.applicableNodeIds.isNotEmpty) {
        final cartNodeIds = _collectCartNodeIds();
        final stillEligible = cartNodeIds
            .any((id) => _appliedCoupon!.applicableNodeIds.contains(id));
        if (!stillEligible) {
          _appliedCoupon = null;
          _couponApplied = false;
          _couponError =
              'Coupon removed - no eligible items remaining in the booking';
        }
      }
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

  Future<void> _pickDate() async {
    if (_primaryServiceId == null) return;
    final picked = await showDatePicker(
      context: context,
      initialDate: _serviceDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null && mounted) {
      setState(() {
        _serviceDate = picked;
        _scheduledTime = null;
        _slotsFuture = AdminSlotService.fetchSlots(
          ref.read(supabaseClientProvider),
          _primaryServiceId!,
          picked,
        );
      });
    }
  }

  Future<void> _pickLocation() async {
    final result = await showDialog<VendorLocationPickerResult>(
      context: context,
      builder: (_) => VendorLocationPickerDialog(
        initialLatitude: _latitude,
        initialLongitude: _longitude,
      ),
    );
    if (result != null) {
      setState(() {
        _latitude = result.latitude;
        _longitude = result.longitude;
        if (_addressCtrl.text.trim().isEmpty) {
          _addressCtrl.text = result.address ?? result.city ?? '';
        }
      });
    }
  }

  Widget _buildCustomerPicker() {
    if (_selectedCustomer != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.person_rounded, size: 16, color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _selectedCustomer!.name,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    _selectedCustomer!.phone,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            InkWell(
              onTap: () => setState(() {
                _selectedCustomer = null;
                _customerSearchCtrl.clear();
                _customerSearchResults = [];
              }),
              borderRadius: BorderRadius.circular(4),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.close_rounded,
                    size: 14, color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextFormField(
          controller: _customerSearchCtrl,
          decoration: InputDecoration(
            labelText: 'Customer *',
            hintText: 'Search by name, phone or email',
            prefixIcon: const Icon(Icons.person_search_outlined),
            isDense: true,
            suffixIcon: _customerSearching
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : (_customerSearchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 16),
                        onPressed: () {
                          _customerSearchCtrl.clear();
                          setState(() => _customerSearchResults = []);
                        },
                        visualDensity: VisualDensity.compact,
                      )
                    : null),
          ),
          onChanged: _onCustomerSearchChanged,
        ),
        if (_customerSearchResults.isNotEmpty) ...[
          const SizedBox(height: 2),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius:
                  const BorderRadius.vertical(bottom: Radius.circular(8)),
              border: Border.all(color: AppColors.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: List.generate(_customerSearchResults.length, (i) {
                final c = _customerSearchResults[i];
                return InkWell(
                  onTap: () => setState(() {
                    _selectedCustomer = c;
                    _customerSearchResults = [];
                    _customerSearchCtrl.clear();
                  }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      border: i < _customerSearchResults.length - 1
                          ? const Border(
                              bottom: BorderSide(
                                  color: AppColors.border, width: 0.5))
                          : null,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              c.name.isNotEmpty
                                  ? c.name[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                c.name,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              Text(
                                c.email != null && c.email!.isNotEmpty
                                    ? '${c.phone} · ${c.email}'
                                    : c.phone,
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSlotPicker() {
    final hasService = (_primaryServiceId ?? '').isNotEmpty;
    final hasDate = _serviceDate != null;

    if (!hasService || !hasDate || _slotsFuture == null) {
      return TextFormField(
        initialValue: _scheduledTime,
        onChanged: (v) =>
            setState(() => _scheduledTime = v.trim().isEmpty ? null : v.trim()),
        decoration: InputDecoration(
          labelText: 'Time Slot',
          hintText: hasService && hasDate ? 'e.g. 10:00 AM' : 'Select service & date first',
          prefixIcon: const Icon(Icons.access_time_rounded),
          isDense: true,
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
                height: 14, child: LinearProgressIndicator()),
          );
        }
        final slots = snap.data ?? [];
        if (slots.isNotEmpty) {
          return DropdownButtonFormField<String>(
            key: ValueKey('slot_${_serviceDate?.toIso8601String()}'),
            // ignore: deprecated_member_use
            value: slots.contains(_scheduledTime) ? _scheduledTime : null,
            hint: const Text('Select time slot'),
            decoration: const InputDecoration(
              labelText: 'Time Slot',
              prefixIcon: Icon(Icons.access_time_rounded),
              isDense: true,
            ),
            items: slots
                .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                .toList(),
            onChanged: (v) => setState(() => _scheduledTime = v),
          );
        }
        return TextFormField(
          initialValue: _scheduledTime,
          onChanged: (v) =>
              setState(() => _scheduledTime = v.trim().isEmpty ? null : v.trim()),
          decoration: const InputDecoration(
            labelText: 'Time Slot',
            hintText: 'e.g. 10:00 AM',
            prefixIcon: Icon(Icons.access_time_rounded),
            isDense: true,
          ),
        );
      },
    );
  }

  // -- Coupon handling -----------------------------------------------------------

  void _applyCoupon() {
    final code = _couponCtrl.text.trim().toUpperCase();
    if (code.isEmpty) return;

    final coupons = ref.read(couponsNotifierProvider).valueOrNull ?? [];
    final coupon = coupons.where((c) => c.code.toUpperCase() == code).firstOrNull;

    if (coupon == null) {
      setState(() {
        _couponError = 'Coupon "$code" not found';
        _appliedCoupon = null;
        _couponApplied = false;
      });
      return;
    }

    if (!coupon.isActive) {
      setState(() {
        _couponError = 'This coupon is inactive';
        _appliedCoupon = null;
        _couponApplied = false;
      });
      return;
    }

    if (coupon.isExpired) {
      setState(() {
        _couponError = 'This coupon has expired';
        _appliedCoupon = null;
        _couponApplied = false;
      });
      return;
    }

    if (coupon.isUsageLimitReached) {
      setState(() {
        _couponError = 'This coupon has reached its usage limit';
        _appliedCoupon = null;
        _couponApplied = false;
      });
      return;
    }

    // Applicability - same logic as customer app's CouponModel.validate()
    if (coupon.applicabilityType != 'all' &&
        coupon.applicableNodeIds.isNotEmpty) {
      final cartNodeIds = _collectCartNodeIds();
      if (cartNodeIds.isNotEmpty) {
        final applicable = cartNodeIds
            .any((id) => coupon.applicableNodeIds.contains(id));
        if (!applicable) {
          setState(() {
            _couponError =
                'This coupon is not applicable to the selected services';
            _appliedCoupon = null;
            _couponApplied = false;
          });
          return;
        }
      }
    }

    final sub = _computeSubtotal();
    if (coupon.minOrderAmount != null && sub < coupon.minOrderAmount!) {
      setState(() {
        _couponError =
            'Minimum order amount is ${_priceFmt.format(coupon.minOrderAmount!)}';
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

  // -- Totals computation --------------------------------------------------------

  double _computeSubtotal() {
    double total = 0.0;
    for (final key in _itemKeys) {
      final s = key.currentState;
      if (s != null) {
        total += s.lineTotal + s.addonsTotal;
      }
    }
    for (final key in _customItemKeys) {
      final s = key.currentState;
      if (s != null) {
        total += s.lineTotal;
      }
    }
    return total;
  }

  double _computeDiscount(double subtotal) {
    if (_appliedCoupon == null) return 0.0;
    final c = _appliedCoupon!;
    // Discount is applied only to the eligible portion of the booking,
    // matching the customer app's per-item applicability behaviour.
    final eligibleSub = _computeEligibleSubtotal(c);
    double disc = c.discountType == 'percentage'
        ? eligibleSub * c.discountValue / 100.0
        : c.discountValue;
    if (c.maxDiscountAmount != null && disc > c.maxDiscountAmount!) {
      disc = c.maxDiscountAmount!;
    }
    return disc.clamp(0.0, eligibleSub);
  }

  double _computeTax(double taxable, TaxSettingsConfig tax) {
    if (!tax.isEnabled) return 0.0;
    return tax.taxType == 'percentage'
        ? taxable * tax.taxValue / 100.0
        : tax.taxValue;
  }

  // -- Submit --------------------------------------------------------------------

  Future<void> _submit(TaxSettingsConfig tax) async {
    if (_selectedCustomer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a customer')),
      );
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    if (_serviceDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a service date')),
      );
      return;
    }

    // Must have at least one item (catalog or custom)
    if (_itemKeys.isEmpty && _customItemKeys.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least one item')),
      );
      return;
    }

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
      if (data == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Item ${i + 1}: Please select a service to continue'),
          ),
        );
        return;
      }
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

    for (int i = 0; i < _customItemKeys.length; i++) {
      final state = _customItemKeys[i].currentState;
      if (state == null) continue;
      final name = state.productName;
      final price = state.price;
      final qty = state.quantity;
      if (name.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Custom item ${i + 1}: Product name required')),
        );
        return;
      }
      if (price <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Custom item ${i + 1}: Valid price required')),
        );
        return;
      }
      bookingItems.add((
        serviceId: '',
        customName: name,
        customCategoryName: state.categoryName.isEmpty ? null : state.categoryName,
        quantity: qty,
        unitPrice: price,
      ));
    }

    final subtotal = _computeSubtotal();
    final discAmt = _computeDiscount(subtotal);
    final taxable = subtotal - discAmt;
    final taxAmt = _computeTax(taxable, tax);

    setState(() => _creating = true);
    try {
      await widget.onCreate(
        customerId: _selectedCustomer!.id,
        serviceDate: _serviceDate!,
        address: _addressCtrl.text.trim(),
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        scheduledTime: _scheduledTime,
        latitude: _latitude,
        longitude: _longitude,
        items: bookingItems,
        addons: allAddons,
        discountAmount: discAmt,
        taxAmount: taxAmt,
        couponCode: _appliedCoupon?.code,
      );
      if (mounted) Navigator.of(context).pop();
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
      if (mounted) setState(() => _creating = false);
    }
  }

  // -- Build ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final taxAsync = ref.watch(_taxSettingsFutureProvider);
    final tax = taxAsync.valueOrNull ?? TaxSettingsConfig.defaults();

    final subtotal = _computeSubtotal();
    final discAmt = _computeDiscount(subtotal);
    final taxable = subtotal - discAmt;
    final taxAmt = _computeTax(taxable, tax);
    final total = (taxable + taxAmt).clamp(0.0, double.infinity);

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Create Booking',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'Multiple services across categories supported',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 720,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // -- Customer + Address --------------------------------------
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _buildCustomerPicker()),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _addressCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Address *',
                                prefixIcon: Icon(Icons.location_on_outlined),
                                isDense: true,
                              ),
                              textCapitalization: TextCapitalization.sentences,
                              validator: (v) =>
                                  v == null || v.trim().isEmpty
                                      ? 'Required'
                                      : null,
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
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // -- Booking Items -------------------------------------------
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
                      onPressed: _addItem,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Add Service'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    const SizedBox(width: 6),
                    TextButton.icon(
                      onPressed: _addCustomItem,
                      icon: const Icon(Icons.add_box_outlined, size: 18),
                      label: const Text('Add Custom Product'),
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
                  _BookingItemRow(
                    key: _itemKeys[i],
                    index: i,
                    canRemove:
                        _itemKeys.length > 1 || _customItemKeys.isNotEmpty,
                    onRemove: () => _removeItem(i),
                    onChanged: _onItemChanged,
                  ),
                ],
                for (var i = 0; i < _customItemKeys.length; i++) ...[
                  const SizedBox(height: 12),
                  _CustomItemRow(
                    key: _customItemKeys[i],
                    index: _itemKeys.length + i,
                    canRemove: true,
                    onRemove: () => _removeCustomItem(i),
                    onChanged: _onItemChanged,
                  ),
                ],
                const SizedBox(height: 20),
                // -- Date + Time Slot ----------------------------------------
                Row(
                  children: [
                    Expanded(
                      child: Tooltip(
                        message: _primaryServiceId == null
                            ? 'Select a service above first'
                            : '',
                        child: InkWell(
                          onTap: _primaryServiceId != null ? _pickDate : null,
                          borderRadius: BorderRadius.circular(8),
                          child: InputDecorator(
                            decoration: InputDecoration(
                              labelText: 'Service Date *',
                              prefixIcon:
                                  const Icon(Icons.calendar_today_rounded),
                              isDense: true,
                              enabled: _primaryServiceId != null,
                            ),
                            child: Text(
                              _serviceDate != null
                                  ? _dateFmt.format(_serviceDate!)
                                  : (_primaryServiceId == null
                                      ? 'Select a service first'
                                      : 'Select date'),
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
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: _buildSlotPicker()),
                  ],
                ),
                const SizedBox(height: 12),
                // -- Notes ---------------------------------------------------
                TextFormField(
                  controller: _notesCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Notes',
                    hintText: 'Optional',
                    prefixIcon: Icon(Icons.notes_rounded),
                    isDense: true,
                  ),
                  textCapitalization: TextCapitalization.sentences,
                ),
                const SizedBox(height: 20),
                // -- Coupon --------------------------------------------------
                const Text(
                  'Coupon / Discount',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                _CouponRow(
                  controller: _couponCtrl,
                  appliedCoupon: _appliedCoupon,
                  couponError: _couponError,
                  isApplied: _couponApplied,
                  onApply: _applyCoupon,
                  onRemove: _removeCoupon,
                  onBrowse: _openCouponBrowser,
                ),
                const SizedBox(height: 20),
                // -- Summary -------------------------------------------------
                _SummaryBox(
                  subtotal: subtotal,
                  discountAmount: discAmt,
                  couponCode: _appliedCoupon?.code,
                  taxName: tax.taxName,
                  taxAmount: taxAmt,
                  taxLabel: tax.isEnabled
                      ? (tax.taxType == 'percentage'
                          ? '${tax.taxName} (${tax.taxValue.toInt()}%)'
                          : tax.taxName)
                      : null,
                  total: total,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _creating ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _creating ? null : () => _submit(tax),
          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
          child: _creating
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Create Booking'),
        ),
      ],
    );
  }
}

// -- Coupon row ----------------------------------------------------------------

class _CouponRow extends StatelessWidget {
  const _CouponRow({
    required this.controller,
    required this.appliedCoupon,
    required this.couponError,
    required this.isApplied,
    required this.onApply,
    required this.onRemove,
    this.onBrowse,
  });

  final TextEditingController controller;
  final Coupon? appliedCoupon;
  final String? couponError;
  final bool isApplied;
  final VoidCallback onApply;
  final VoidCallback onRemove;
  final VoidCallback? onBrowse;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                controller: controller,
                enabled: !isApplied,
                decoration: InputDecoration(
                  labelText: 'Coupon Code',
                  hintText: 'Enter code',
                  prefixIcon: const Icon(Icons.discount_outlined),
                  isDense: true,
                  suffixIcon: isApplied
                      ? const Icon(Icons.check_circle_rounded,
                          color: AppColors.success, size: 20)
                      : null,
                  errorText: couponError,
                ),
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[A-Z0-9a-z_\-]')),
                  _UpperCaseFormatter(),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (!isApplied) ...[
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: FilledButton(
                  onPressed: onApply,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 13),
                  ),
                  child: const Text('Apply'),
                ),
              ),
              if (onBrowse != null) ...[
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: OutlinedButton.icon(
                    onPressed: onBrowse,
                    icon: const Icon(Icons.local_offer_rounded, size: 14),
                    label: const Text('Browse'),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 13),
                    ),
                  ),
                ),
              ],
            ] else
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: OutlinedButton.icon(
                  onPressed: onRemove,
                  icon: const Icon(Icons.close_rounded, size: 16),
                  label: const Text('Remove'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: const BorderSide(color: AppColors.error),
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 13),
                  ),
                ),
              ),
          ],
        ),
        if (isApplied && appliedCoupon != null) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: AppColors.success.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.local_offer_rounded,
                    size: 14, color: AppColors.success),
                const SizedBox(width: 6),
                Text(
                  '${appliedCoupon!.code} applied - '
                  '${appliedCoupon!.discountType == 'percentage' ? '${appliedCoupon!.discountValue.toInt()}% off' : '₹${appliedCoupon!.discountValue.toInt()} off'}',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.success,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// -- Summary box ---------------------------------------------------------------

class _SummaryBox extends StatelessWidget {
  const _SummaryBox({
    required this.subtotal,
    required this.discountAmount,
    required this.couponCode,
    required this.taxName,
    required this.taxAmount,
    required this.taxLabel,
    required this.total,
  });

  final double subtotal;
  final double discountAmount;
  final String? couponCode;
  final String taxName;
  final double taxAmount;
  final String? taxLabel;
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
          _SummaryRow(
            label: 'Subtotal',
            value: _priceFmt.format(subtotal),
          ),
          if (discountAmount > 0) ...[
            const SizedBox(height: 6),
            _SummaryRow(
              label: couponCode != null
                  ? 'Discount ($couponCode)'
                  : 'Discount',
              value: 'âˆ’${_priceFmt.format(discountAmount)}',
              valueColor: AppColors.success,
            ),
          ],
          if (taxLabel != null) ...[
            const SizedBox(height: 6),
            _SummaryRow(
              label: taxLabel!,
              value: _priceFmt.format(taxAmount),
            ),
          ],
          const SizedBox(height: 10),
          const Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 10),
          _SummaryRow(
            label: 'Total',
            value: _priceFmt.format(total),
            labelBold: true,
            valueBold: true,
            valueColor: AppColors.primary,
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
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
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
              fontWeight: labelBold ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: valueBold ? 15 : 13,
            fontWeight: valueBold ? FontWeight.w700 : FontWeight.w500,
            color: valueColor ?? AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

// -- Booking item row ---------------------------------------------------------

class _BookingItemRow extends ConsumerStatefulWidget {
  const _BookingItemRow({
    super.key,
    required this.index,
    required this.canRemove,
    required this.onRemove,
    required this.onChanged,
  });

  final int index;
  final bool canRemove;
  final VoidCallback onRemove;
  final VoidCallback onChanged;

  @override
  ConsumerState<_BookingItemRow> createState() => _BookingItemRowState();
}

class _BookingItemRowState extends ConsumerState<_BookingItemRow> {
  CatalogNode? _category;
  CatalogNode? _subCat;
  CatalogNode? _service;
  int _quantity = 1;
  List<ServiceAddon> _nodeAddons = [];
  Set<String> _selectedAddonIds = {};
  bool _loadingAddons = false;

  String? get currentServiceId => _service?.id;

  double get lineTotal => (_service?.basePrice ?? 0.0) * _quantity;

  // Returns this item's node ID + all ancestor IDs - used for coupon applicability.
  List<String> get nodeIds {
    if (_service == null) return const [];
    return [_service!.id, ..._service!.parentIds];
  }

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

  Future<void> _fetchAddons(String nodeId) async {
    try {
      final addons =
          await ref.read(serviceAddonsRepositoryProvider).fetchNodeAddons(nodeId);
      if (mounted) {
        setState(() {
          _nodeAddons = addons.where((a) => a.isActive).toList();
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
                n.isActive &&
                n.isBookable)
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
          // Header
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
                  icon: const Icon(
                    Icons.remove_circle_outline_rounded,
                    size: 18,
                  ),
                  color: AppColors.error,
                  tooltip: 'Remove item',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
            ],
          ),
          const SizedBox(height: 12),
          // Cascading dropdowns
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _CatalogDropdown(
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
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: AppColors.textSecondary,
                ),
              ),
              Expanded(
                child: _CatalogDropdown(
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
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: AppColors.textSecondary,
                ),
              ),
              Expanded(
                child: _CatalogDropdown(
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
          if (resolvedService != null) ...[
            const SizedBox(height: 12),
            // Price + Qty + Line total
            Row(
              children: [
                Expanded(
                  child: _InfoBox(
                    label: 'Unit Price',
                    value: price != null ? _priceFmt.format(price) : '-',
                    valueColor: AppColors.textPrimary,
                    bgColor: AppColors.surface,
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Qty',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _QtyButton(
                        icon: Icons.remove_rounded,
                        onTap: _quantity > 1
                            ? () {
                                setState(() => _quantity--);
                                widget.onChanged();
                              }
                            : null,
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Text(
                          '$_quantity',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      _QtyButton(
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
                  child: _InfoBox(
                    label: 'Line Total',
                    value: price != null
                        ? _priceFmt.format(price * _quantity)
                        : '-',
                    valueColor: AppColors.primary,
                    bgColor: AppColors.primary.withValues(alpha: 0.06),
                    borderColor: AppColors.primary.withValues(alpha: 0.2),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Add-ons
            if (_loadingAddons)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else if (_nodeAddons.isNotEmpty) ...[
              Row(
                children: [
                  const Text(
                    'Add-ons',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    '(optional)',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  if (_selectedAddonIds.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${_selectedAddonIds.length}',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: _nodeAddons.map((addon) {
                  final selected = _selectedAddonIds.contains(addon.id);
                  return _AddonChip(
                    addon: addon,
                    isSelected: selected,
                    onToggle: () {
                      setState(() {
                        if (selected) {
                          _selectedAddonIds.remove(addon.id);
                        } else {
                          _selectedAddonIds.add(addon.id);
                        }
                      });
                      widget.onChanged();
                    },
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

// -- Custom item row -----------------------------------------------------------

class _CustomItemRow extends StatefulWidget {
  const _CustomItemRow({
    super.key,
    required this.index,
    required this.canRemove,
    required this.onRemove,
    required this.onChanged,
  });

  final int index;
  final bool canRemove;
  final VoidCallback onRemove;
  final VoidCallback onChanged;

  @override
  State<_CustomItemRow> createState() => _CustomItemRowState();
}

class _CustomItemRowState extends State<_CustomItemRow> {
  final _categoryCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  int _quantity = 1;

  String get categoryName => _categoryCtrl.text.trim();
  String get productName => _nameCtrl.text.trim();
  double get price => double.tryParse(_priceCtrl.text.trim()) ?? 0.0;
  int get quantity => _quantity;
  double get lineTotal => price * _quantity;

  @override
  void dispose() {
    _categoryCtrl.dispose();
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

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
          // Header
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.textSecondary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Item ${widget.index + 1}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFD4AF37).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Custom',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFD4AF37),
                  ),
                ),
              ),
              const Spacer(),
              if (widget.canRemove)
                IconButton(
                  onPressed: widget.onRemove,
                  icon: const Icon(
                    Icons.remove_circle_outline_rounded,
                    size: 18,
                  ),
                  color: AppColors.error,
                  tooltip: 'Remove item',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _categoryCtrl,
            decoration: const InputDecoration(
              labelText: 'Category Name (optional)',
              hintText: 'e.g. Home Cleaning',
              isDense: true,
            ),
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => widget.onChanged(),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Product name
              Expanded(
                flex: 2,
                child: TextFormField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Product Name *',
                    hintText: 'Enter product name',
                    isDense: true,
                  ),
                  textCapitalization: TextCapitalization.words,
                  onChanged: (_) => widget.onChanged(),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Required' : null,
                ),
              ),
              const SizedBox(width: 10),
              // Unit price
              Expanded(
                child: TextFormField(
                  controller: _priceCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Unit Price *',
                    prefixText: '₹ ',
                    isDense: true,
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                        RegExp(r'^\d+\.?\d{0,2}')),
                  ],
                  onChanged: (_) => widget.onChanged(),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Required';
                    final d = double.tryParse(v.trim());
                    if (d == null || d <= 0) return 'Invalid';
                    return null;
                  },
                ),
              ),
              const SizedBox(width: 10),
              // Qty stepper
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Qty',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _QtyButton(
                      icon: Icons.remove_rounded,
                      onTap: _quantity > 1
                          ? () {
                              setState(() => _quantity--);
                              widget.onChanged();
                            }
                          : null,
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Text(
                        '$_quantity',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    _QtyButton(
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
              // Line total
              Expanded(
                child: _InfoBox(
                  label: 'Line Total',
                  value: price > 0 ? _priceFmt.format(lineTotal) : '-',
                  valueColor: AppColors.primary,
                  bgColor: AppColors.primary.withValues(alpha: 0.06),
                  borderColor: AppColors.primary.withValues(alpha: 0.2),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// -- Catalog dropdown ---------------------------------------------------------

class _CatalogDropdown extends StatelessWidget {
  const _CatalogDropdown({
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
  final ValueChanged<CatalogNode?> onChanged;

  @override
  Widget build(BuildContext context) {
    final value = selectedId != null
        ? nodes.where((n) => n.id == selectedId).firstOrNull
        : null;

    return DropdownButtonFormField<CatalogNode>(
      initialValue: value,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      hint: Text(hint, style: const TextStyle(fontSize: 13)),
      isExpanded: true,
      items: nodes
          .map((node) => DropdownMenuItem<CatalogNode>(
                value: node,
                child: Text(
                  node.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
              ))
          .toList(),
      onChanged: enabled ? onChanged : null,
      disabledHint: Text(
        nodes.isEmpty ? '-' : hint,
        style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
      ),
    );
  }
}

// -- Info box -----------------------------------------------------------------

class _InfoBox extends StatelessWidget {
  const _InfoBox({
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor ?? AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}

// -- Quantity button -----------------------------------------------------------

class _QtyButton extends StatelessWidget {
  const _QtyButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: onTap != null
              ? AppColors.primary.withValues(alpha: 0.1)
              : AppColors.border,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(
          icon,
          size: 14,
          color: onTap != null ? AppColors.primary : AppColors.textSecondary,
        ),
      ),
    );
  }
}

// -- Addon chip ----------------------------------------------------------------

class _AddonChip extends StatelessWidget {
  const _AddonChip({
    required this.addon,
    required this.isSelected,
    required this.onToggle,
  });

  final ServiceAddon addon;
  final bool isSelected;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.08)
              : AppColors.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSelected
                  ? Icons.check_box_rounded
                  : Icons.check_box_outline_blank_rounded,
              size: 16,
              color: isSelected ? AppColors.primary : AppColors.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              addon.name,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected ? AppColors.primary : AppColors.textPrimary,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '+ ₹${addon.price.toInt()}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isSelected
                    ? const Color(0xFFD4AF37)
                    : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -- Upper-case text formatter -------------------------------------------------

class _UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
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

// ── Customer search result ────────────────────────────────────────────────────

class _CustomerResult {
  final String id;
  final String name;
  final String phone;
  final String? email;

  const _CustomerResult({
    required this.id,
    required this.name,
    required this.phone,
    this.email,
  });
}
