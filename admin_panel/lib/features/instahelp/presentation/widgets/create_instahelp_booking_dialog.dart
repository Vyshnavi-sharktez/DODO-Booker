import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../auth/application/providers/auth_provider.dart';
import '../../../customers/domain/models/customer_address.dart';
import '../../../vendors/presentation/widgets/vendor_location_picker_dialog.dart';
import '../../application/providers/instahelp_providers.dart';
import '../../domain/models/instahelp_duration.dart';
import '../../domain/models/instahelp_mode.dart';

class AdminCreateInstaHelpBookingDialog extends ConsumerStatefulWidget {
  const AdminCreateInstaHelpBookingDialog({super.key});

  @override
  ConsumerState<AdminCreateInstaHelpBookingDialog> createState() =>
      _AdminCreateInstaHelpBookingDialogState();
}

class _AdminCreateInstaHelpBookingDialogState
    extends ConsumerState<AdminCreateInstaHelpBookingDialog> {
  final _formKey = GlobalKey<FormState>();
  final _customerSearchCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();

  // Customer search
  _CustomerResult? _selectedCustomer;
  List<_CustomerResult> _searchResults = [];
  bool _searching = false;
  Timer? _searchDebounce;

  // Customer saved addresses
  List<CustomerAddress> _customerAddresses = [];
  CustomerAddress? _selectedAddress;
  bool _addressLoading = false;

  double? _latitude;
  double? _longitude;

  // Vendors near the selected address
  List<_NearbyVendor> _nearbyVendors = [];
  bool _loadingNearbyVendors = false;
  String? _vendorLoadError;
  bool _showAllVendors = false;

  _NearbyVendor? _selectedVendor;
  InstaHelpMode? _selectedMode;
  InstaHelpDuration? _selectedDuration;
  DateTime? _selectedDate;
  String? _selectedSlot;
  String _paymentMethod = 'cash';

  bool _saving = false;
  String? _error;

  List<InstaHelpMode> _vendorModes = [];
  bool _loadingModes = false;
  List<String> _slots = [];
  double _gstPercent = 0;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _customerSearchCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  // ── Customer search ───────────────────────────────────────────────────────

  void _onSearchChanged(String q) {
    _searchDebounce?.cancel();
    final query = q.trim();
    if (query.length < 2) {
      if (_searchResults.isNotEmpty) setState(() => _searchResults = []);
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 300), () => _search(query));
  }

  Future<void> _search(String q) async {
    setState(() => _searching = true);
    try {
      final rows = await ref.read(supabaseClientProvider)
          .from('customers')
          .select('id, full_name, phone, email')
          .or('full_name.ilike.%$q%,phone.ilike.%$q%,email.ilike.%$q%')
          .limit(6);
      if (mounted) {
        setState(() {
          _searchResults = (rows as List).map((r) {
            final m = r as Map<String, dynamic>;
            return _CustomerResult(
              id: m['id'] as String,
              name: (m['full_name'] as String?) ?? '—',
              phone: (m['phone'] as String?) ?? '',
              email: m['email'] as String?,
            );
          }).toList();
          _searching = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _selectCustomer(_CustomerResult c) {
    setState(() {
      _selectedCustomer = c;
      _searchResults = [];
      _customerSearchCtrl.clear();
      _customerAddresses = [];
      _selectedAddress = null;
      _addressCtrl.clear();
      _latitude = null;
      _longitude = null;
      _nearbyVendors = [];
      _selectedVendor = null;
      _selectedMode = null;
      _selectedDuration = null;
      _vendorLoadError = null;
      _showAllVendors = false;
    });
    _loadAddresses(c.id);
  }

  void _clearCustomer() {
    setState(() {
      _selectedCustomer = null;
      _searchResults = [];
      _customerSearchCtrl.clear();
      _customerAddresses = [];
      _selectedAddress = null;
      _addressCtrl.clear();
      _latitude = null;
      _longitude = null;
      _nearbyVendors = [];
      _selectedVendor = null;
      _selectedMode = null;
      _selectedDuration = null;
      _vendorLoadError = null;
      _showAllVendors = false;
    });
  }

  Future<void> _loadAddresses(String customerId) async {
    setState(() => _addressLoading = true);
    try {
      final rows = await ref.read(supabaseClientProvider)
          .from('customer_addresses')
          .select()
          .eq('customer_id', customerId)
          .order('is_default', ascending: false);
      if (!mounted) return;
      final addresses = (rows as List)
          .map((r) => CustomerAddress.fromMap(r as Map<String, dynamic>))
          .toList();
      CustomerAddress? def;
      if (addresses.isNotEmpty) {
        def = addresses.firstWhere((a) => a.isDefault, orElse: () => addresses.first);
        _addressCtrl.text = def.fullAddress;
        _latitude = def.latitude;
        _longitude = def.longitude;
      }
      setState(() {
        _customerAddresses = addresses;
        _selectedAddress = def;
        _addressLoading = false;
      });
      _loadNearbyVendors();
    } catch (_) {
      if (mounted) setState(() => _addressLoading = false);
    }
  }

  // ── Location picker ───────────────────────────────────────────────────────

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
        _addressCtrl.text = result.address ?? result.city ?? '';
        _selectedAddress = null;
        _selectedVendor = null;
        _selectedMode = null;
        _selectedDuration = null;
      });
      _loadNearbyVendors();
    }
  }

  // ── Nearby vendors ────────────────────────────────────────────────────────

  Future<void> _loadNearbyVendors() async {
    if (_latitude == null || _longitude == null) {
      setState(() {
        _nearbyVendors = [];
        _selectedVendor = null;
        _vendorLoadError = null;
        _showAllVendors = false;
      });
      return;
    }
    setState(() {
      _loadingNearbyVendors = true;
      _vendorLoadError = null;
      _showAllVendors = false;
    });
    try {
      // Use the 3-param overload explicitly to avoid PostgREST ambiguity.
      final rows = await ref.read(supabaseClientProvider).rpc(
        'get_instahelp_vendors_by_location',
        params: {
          'p_lat': _latitude,
          'p_lng': _longitude,
          'p_mode_type': null,
        },
      );
      if (mounted) {
        final vendors = (rows as List).map((r) {
          final m = r as Map<String, dynamic>;
          return _NearbyVendor(
            id: m['id'].toString(),
            businessName: (m['business_name'] as String?) ?? 'Unknown',
            isOnline: (m['is_online'] as bool?) ?? false,
          );
        }).toList();
        setState(() {
          _nearbyVendors = vendors;
          _loadingNearbyVendors = false;
          // Auto-fallback: if no vendors near this location, load all
          if (vendors.isEmpty) _loadAllInstaHelpVendors();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingNearbyVendors = false;
          _vendorLoadError = e.toString().replaceAll('Exception: ', '');
        });
        _loadAllInstaHelpVendors();
      }
    }
  }

  Future<void> _loadAllInstaHelpVendors() async {
    setState(() => _loadingNearbyVendors = true);
    try {
      // Fetch all vendors that have at least one InstaHelp mode configured.
      final rows = await ref.read(supabaseClientProvider)
          .from('vendors')
          .select('id, business_name, is_online, is_active')
          .eq('is_active', true)
          .order('business_name');
      // Filter to those with any instahelp mode.
      final allVendorIds = (rows as List).map((r) {
        return (r as Map<String, dynamic>)['id'].toString();
      }).toList();
      if (allVendorIds.isEmpty) {
        if (mounted) setState(() => _loadingNearbyVendors = false);
        return;
      }
      final modeRows = await ref.read(supabaseClientProvider)
          .from('instahelp_modes')
          .select('vendor_id')
          .inFilter('vendor_id', allVendorIds);
      final vendorIdsWithModes = (modeRows as List)
          .map((r) => (r as Map<String, dynamic>)['vendor_id'].toString())
          .toSet();
      if (mounted) {
        setState(() {
          _nearbyVendors = (rows as List).where((r) {
            final m = r as Map<String, dynamic>;
            return vendorIdsWithModes.contains(m['id'].toString());
          }).map((r) {
            final m = r as Map<String, dynamic>;
            return _NearbyVendor(
              id: m['id'].toString(),
              businessName: (m['business_name'] as String?) ?? 'Unknown',
              isOnline: (m['is_online'] as bool?) ?? false,
            );
          }).toList();
          _loadingNearbyVendors = false;
          _showAllVendors = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingNearbyVendors = false);
    }
  }

  // ── Modes / durations ─────────────────────────────────────────────────────

  Future<void> _loadVendorModes(String vendorId) async {
    setState(() {
      _loadingModes = true;
      _selectedMode = null;
      _selectedDuration = null;
      _slots = [];
      _selectedSlot = null;
      _selectedDate = null;
    });
    try {
      final data = await Supabase.instance.client
          .from('instahelp_modes')
          .select()
          .eq('vendor_id', vendorId)
          .order('mode_type');
      final modes = (data as List)
          .map((r) => InstaHelpMode.fromMap(r as Map<String, dynamic>))
          .toList();
      if (mounted) {
        setState(() {
          _vendorModes = modes;
          _selectedMode = modes.isNotEmpty ? modes.first : null;
          _loadingModes = false;
          _gstPercent = 0;
        });
        if (_selectedMode != null) {
          ref.read(instaHelpDurationsProvider(_selectedMode!.id).notifier).refresh();
          _loadFinancialConfig(_selectedMode!.id);
        }
      }
    } catch (_) {
      if (mounted) setState(() => _loadingModes = false);
    }
  }

  void _onModeSelected(InstaHelpMode mode) {
    setState(() {
      _selectedMode = mode;
      _selectedDuration = null;
      _slots = [];
      _selectedSlot = null;
      _selectedDate = null;
      _gstPercent = 0;
    });
    ref.read(instaHelpDurationsProvider(mode.id).notifier).refresh();
    _loadFinancialConfig(mode.id);
  }

  Future<void> _loadFinancialConfig(String modeId) async {
    try {
      final rows = await ref.read(supabaseClientProvider)
          .from('instahelp_financial_config')
          .select('gst_percent')
          .eq('mode_id', modeId)
          .limit(1);
      if (mounted && (rows as List).isNotEmpty) {
        final gst = (rows.first as Map<String, dynamic>)['gst_percent'];
        setState(() => _gstPercent = (gst as num?)?.toDouble() ?? 0);
      }
    } catch (_) {}
  }

  void _onDurationSelected(InstaHelpDuration dur) {
    setState(() {
      _selectedDuration = dur;
      _selectedDate = null;
      _slots = [];
      _selectedSlot = null;
    });
  }

  void _onDateSelected(DateTime date) {
    final dur = _selectedDuration;
    final slots = <String>[];
    if (dur != null) {
      final sp = dur.slotStartTime.split(':');
      final ep = dur.slotEndTime.split(':');
      if (sp.length >= 2 && ep.length >= 2) {
        int t = (int.tryParse(sp[0]) ?? 0) * 60 + (int.tryParse(sp[1]) ?? 0);
        final end = (int.tryParse(ep[0]) ?? 0) * 60 + (int.tryParse(ep[1]) ?? 0);
        while (t <= end) {
          slots.add('${(t ~/ 60).toString().padLeft(2, '0')}:${(t % 60).toString().padLeft(2, '0')}');
          t += dur.slotIntervalMinutes;
        }
      }
    }
    setState(() {
      _selectedDate = date;
      _slots = slots;
      _selectedSlot = slots.isNotEmpty ? slots.first : null;
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 90)),
    );
    if (picked != null) _onDateSelected(picked);
  }

  // ── Submit ────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCustomer == null) { setState(() => _error = 'Please select a customer.'); return; }
    if (_selectedVendor == null)   { setState(() => _error = 'Please select a vendor.'); return; }
    if (_selectedMode == null)     { setState(() => _error = 'Please select a mode.'); return; }
    if (_selectedDuration == null) { setState(() => _error = 'Please select a duration.'); return; }
    if (_selectedDate == null)     { setState(() => _error = 'Please select a service date.'); return; }
    if (_addressCtrl.text.trim().isEmpty) { setState(() => _error = 'Please enter an address.'); return; }

    setState(() { _saving = true; _error = null; });
    try {
      final result = await Supabase.instance.client.rpc(
        'create_instahelp_booking_by_admin',
        params: {
          'p_customer_phone': _selectedCustomer!.phone,
          'p_vendor_id':      _selectedVendor!.id,
          'p_mode_id':        _selectedMode!.id,
          'p_duration_id':    _selectedDuration!.id,
          'p_service_date':   DateFormat('yyyy-MM-dd').format(_selectedDate!),
          'p_scheduled_time': _selectedSlot ?? '09:00',
          'p_address':        _addressCtrl.text.trim(),
          'p_payment_method': _paymentMethod,
        },
      );
      final bookingNumber = (result as Map<String, dynamic>)['booking_number'] as String? ?? '';
      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Booking #$bookingNumber created successfully!'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _saving = false;
      });
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 540,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.flash_on_rounded, color: AppColors.primary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Text('Create InstaHelp Booking',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: _saving ? null : () => Navigator.of(context).pop(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ]),
                const SizedBox(height: 20),

                Flexible(
                  child: SingleChildScrollView(child: _buildForm()),
                ),

                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 12)),
                  ),
                ],

                const SizedBox(height: 20),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving ? null : () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _saving ? null : _submit,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        minimumSize: const Size(0, 44),
                      ),
                      child: _saving
                          ? const SizedBox(width: 18, height: 18,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Text('Create Booking'),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Customer search ─────────────────────────────────────────────────
        _buildCustomerPicker(),
        const SizedBox(height: 16),

        // ── Address ─────────────────────────────────────────────────────────
        if (_addressLoading)
          const LinearProgressIndicator(minHeight: 2),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _buildAddressField()),
            const SizedBox(width: 8),
            _buildMapButton(),
          ],
        ),
        const SizedBox(height: 16),

        // ── Vendor dropdown ──────────────────────────────────────────────────
        _buildVendorField(),
        const SizedBox(height: 16),

        // ── Mode chips ───────────────────────────────────────────────────────
        if (_selectedVendor != null) ...[
          const Text('Mode', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          if (_loadingModes)
            const LinearProgressIndicator()
          else if (_vendorModes.isEmpty)
            const Text('No InstaHelp modes configured for this vendor.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary))
          else
            Wrap(
              spacing: 8,
              children: _vendorModes.map((m) {
                final sel = _selectedMode?.id == m.id;
                return ChoiceChip(
                  label: Text(m.displayName),
                  selected: sel,
                  onSelected: (_) => _onModeSelected(m),
                  selectedColor: AppColors.primary.withValues(alpha: 0.15),
                  labelStyle: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: sel ? AppColors.primary : AppColors.textSecondary,
                  ),
                );
              }).toList(),
            ),
          const SizedBox(height: 16),
        ],

        // ── Duration picker ──────────────────────────────────────────────────
        if (_selectedMode != null) ...[
          _DurationPicker(
            modeId: _selectedMode!.id,
            selectedId: _selectedDuration?.id,
            onSelected: _onDurationSelected,
          ),
          const SizedBox(height: 16),
        ],

        // ── Date picker ──────────────────────────────────────────────────────
        _FieldTile(
          label: _selectedDate != null
              ? DateFormat('dd MMM yyyy').format(_selectedDate!)
              : 'Select service date *',
          icon: Icons.calendar_today_rounded,
          muted: _selectedDate == null,
          onTap: _pickDate,
        ),
        const SizedBox(height: 16),

        // ── Time slot ────────────────────────────────────────────────────────
        if (_selectedDate != null && _slots.isNotEmpty) ...[
          const Text('Time Slot', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade400),
              borderRadius: BorderRadius.circular(4),
            ),
            child: DropdownButton<String>(
              value: _selectedSlot,
              isExpanded: true,
              underline: const SizedBox.shrink(),
              items: _slots.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
              onChanged: (v) => setState(() => _selectedSlot = v),
            ),
          ),
          const SizedBox(height: 16),
        ],

        // ── Payment method ───────────────────────────────────────────────────
        const Text('Payment Method', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
        const SizedBox(height: 8),
        Row(children: [
          _PayChip(label: 'Cash', selected: _paymentMethod == 'cash', onTap: () => setState(() => _paymentMethod = 'cash')),
          const SizedBox(width: 8),
          _PayChip(label: 'Online', selected: _paymentMethod == 'online', onTap: () => setState(() => _paymentMethod = 'online')),
        ]),

        // ── Price preview ────────────────────────────────────────────────────
        if (_selectedDuration != null) ...[
          const SizedBox(height: 16),
          Builder(builder: (_) {
            final subtotal = _selectedDuration!.finalPrice;
            final gstAmount = (_gstPercent > 0) ? (subtotal * _gstPercent / 100.0) : 0.0;
            final total = subtotal + gstAmount;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('Subtotal', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                  Text('₹${subtotal.toStringAsFixed(0)}',
                      style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                ]),
                if (_gstPercent > 0) ...[
                  const SizedBox(height: 4),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text('GST (${_gstPercent.toStringAsFixed(0)}%)',
                        style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                    Text('₹${gstAmount.toStringAsFixed(0)}',
                        style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                  ]),
                  Divider(height: 12, color: AppColors.primary.withValues(alpha: 0.2)),
                ],
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('Total', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  Text('₹${total.toStringAsFixed(0)}',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.primary)),
                ]),
              ]),
            );
          }),
        ],
      ],
    );
  }

  // ── Vendor field (location-aware) ─────────────────────────────────────────

  Widget _buildVendorField() {
    if (_latitude == null || _longitude == null) {
      return InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Vendor *',
          border: OutlineInputBorder(),
          isDense: true,
          prefixIcon: Icon(Icons.store_rounded, size: 18),
        ),
        child: const Text(
          'Select address first to see available vendors',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary, fontStyle: FontStyle.italic),
        ),
      );
    }
    if (_loadingNearbyVendors) {
      return const InputDecorator(
        decoration: InputDecoration(
          labelText: 'Vendor *',
          border: OutlineInputBorder(),
          isDense: true,
          prefixIcon: Icon(Icons.store_rounded, size: 18),
        ),
        child: LinearProgressIndicator(minHeight: 2),
      );
    }
    if (_nearbyVendors.isEmpty) {
      return InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Vendor *',
          border: OutlineInputBorder(),
          isDense: true,
          prefixIcon: Icon(Icons.store_outlined, size: 18),
        ),
        child: const Text(
          'No InstaHelp vendors found — loading all…',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary, fontStyle: FontStyle.italic),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_showAllVendors)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              const Icon(Icons.info_outline_rounded, size: 13, color: AppColors.textSecondary),
              const SizedBox(width: 4),
              Expanded(child: Text(
                'No vendors found near this location — showing all InstaHelp vendors',
                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
              )),
            ]),
          ),
        DropdownButtonFormField<_NearbyVendor>(
      value: _selectedVendor,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Vendor *',
        border: OutlineInputBorder(),
        isDense: true,
        prefixIcon: Icon(Icons.store_rounded, size: 18),
      ),
      items: _nearbyVendors.map((v) => DropdownMenuItem(
        value: v,
        child: Row(
          children: [
            Container(
              width: 8, height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: v.isOnline ? AppColors.success : AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(v.businessName, overflow: TextOverflow.ellipsis)),
          ],
        ),
      )).toList(),
      onChanged: (v) {
        if (v == null) return;
        setState(() => _selectedVendor = v);
        _loadVendorModes(v.id);
      },
      validator: (v) => v == null ? 'Required' : null,
    ),
      ],
    );
  }

  // ── Customer picker widget ─────────────────────────────────────────────────

  Widget _buildCustomerPicker() {
    if (_selectedCustomer != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
        ),
        child: Row(children: [
          const Icon(Icons.person_rounded, size: 16, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(_selectedCustomer!.name,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              Text(_selectedCustomer!.phone,
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ]),
          ),
          InkWell(
            onTap: _clearCustomer,
            borderRadius: BorderRadius.circular(4),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.close_rounded, size: 14, color: AppColors.textSecondary),
            ),
          ),
        ]),
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
            border: const OutlineInputBorder(),
            isDense: true,
            suffixIcon: _searching
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)))
                : (_customerSearchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 16),
                        onPressed: () {
                          _customerSearchCtrl.clear();
                          setState(() => _searchResults = []);
                        },
                        visualDensity: VisualDensity.compact,
                      )
                    : null),
          ),
          validator: (_) => _selectedCustomer == null ? 'Select a customer' : null,
          onChanged: _onSearchChanged,
        ),
        if (_searchResults.isNotEmpty) ...[
          const SizedBox(height: 2),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
              border: Border.all(color: AppColors.border),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 6, offset: const Offset(0, 2))],
            ),
            child: Column(
              children: List.generate(_searchResults.length, (i) {
                final c = _searchResults[i];
                return InkWell(
                  onTap: () => _selectCustomer(c),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      border: i < _searchResults.length - 1
                          ? const Border(bottom: BorderSide(color: AppColors.border, width: 0.5))
                          : null,
                    ),
                    child: Row(children: [
                      Container(
                        width: 32, height: 32,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            c.name.isNotEmpty ? c.name[0].toUpperCase() : '?',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.primary),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                          Text(c.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                          Text(
                            c.email != null && c.email!.isNotEmpty ? '${c.phone} · ${c.email}' : c.phone,
                            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                          ),
                        ]),
                      ),
                    ]),
                  ),
                );
              }),
            ),
          ),
        ],
      ],
    );
  }

  // ── Map button ────────────────────────────────────────────────────────────

  Widget _buildMapButton() {
    return Tooltip(
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
                ? AppColors.primary.withValues(alpha: 0.1)
                : AppColors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _latitude != null
                  ? AppColors.primary.withValues(alpha: 0.4)
                  : AppColors.border,
            ),
          ),
          child: Icon(
            Icons.map_outlined,
            size: 18,
            color: _latitude != null ? AppColors.primary : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  // ── Address field ──────────────────────────────────────────────────────────

  Widget _buildAddressField() {
    if (_customerAddresses.isNotEmpty) {
      return DropdownButtonFormField<String?>(
        key: ValueKey('addr_${_selectedAddress?.id ?? '__map__'}'),
        initialValue: _selectedAddress?.id,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Address *',
          border: OutlineInputBorder(),
          isDense: true,
          prefixIcon: Icon(Icons.location_on_rounded, size: 18),
        ),
        validator: (_) => _addressCtrl.text.trim().isEmpty ? 'Required' : null,
        items: [
          ..._customerAddresses.map((a) => DropdownMenuItem<String?>(
                value: a.id,
                child: Text('${a.addressType} · ${a.addressLine1}, ${a.city}',
                    overflow: TextOverflow.ellipsis),
              )),
          DropdownMenuItem<String?>(
            value: null,
            child: Text(
              _addressCtrl.text.isNotEmpty && _selectedAddress == null
                  ? '📍 ${_addressCtrl.text}'
                  : 'Pick on map…',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _addressCtrl.text.isNotEmpty && _selectedAddress == null
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
                fontStyle: _addressCtrl.text.isEmpty || _selectedAddress != null
                    ? FontStyle.italic
                    : FontStyle.normal,
              ),
            ),
          ),
        ],
        onChanged: (val) {
          if (val == null) {
            // "Pick on map" selected — open map picker
            _pickLocation();
            return;
          }
          final addr = _customerAddresses.firstWhere((a) => a.id == val);
          setState(() {
            _selectedAddress = addr;
            _addressCtrl.text = addr.fullAddress;
            _latitude = addr.latitude;
            _longitude = addr.longitude;
            _selectedVendor = null;
            _selectedMode = null;
            _selectedDuration = null;
          });
          _loadNearbyVendors();
        },
      );
    }

    // No saved addresses — read-only display; use map button to set address.
    return FormField<String>(
      validator: (_) => _addressCtrl.text.trim().isEmpty ? 'Required' : null,
      builder: (field) => InputDecorator(
        decoration: InputDecoration(
          labelText: 'Address *',
          prefixIcon: const Icon(Icons.location_on_outlined),
          border: const OutlineInputBorder(),
          isDense: true,
          errorText: field.errorText,
        ),
        child: Text(
          _addressCtrl.text.isNotEmpty
              ? _addressCtrl.text
              : 'Use map button to set address',
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            color: _addressCtrl.text.isNotEmpty
                ? AppColors.textPrimary
                : AppColors.textSecondary,
            fontStyle: _addressCtrl.text.isEmpty ? FontStyle.italic : FontStyle.normal,
          ),
        ),
      ),
    );
  }
}

// ── Duration picker ───────────────────────────────────────────────────────────

class _DurationPicker extends ConsumerWidget {
  final String modeId;
  final String? selectedId;
  final ValueChanged<InstaHelpDuration> onSelected;

  const _DurationPicker({
    required this.modeId,
    required this.selectedId,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(instaHelpDurationsProvider(modeId));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Duration', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
        const SizedBox(height: 8),
        async.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text('Error: $e', style: const TextStyle(color: AppColors.error, fontSize: 12)),
          data: (durations) {
            if (durations.isEmpty) {
              return const Text('No durations configured.',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary));
            }
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: durations.map((d) {
                final sel = selectedId == d.id;
                return GestureDetector(
                  onTap: () => onSelected(d),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: sel ? AppColors.primary.withValues(alpha: 0.1) : Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: sel ? AppColors.primary : Colors.grey.shade300,
                        width: sel ? 2 : 1,
                      ),
                    ),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(d.label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                          color: sel ? AppColors.primary : AppColors.textPrimary)),
                      Text('₹${d.finalPrice.toStringAsFixed(0)}', style: TextStyle(fontSize: 11,
                          color: sel ? AppColors.primary : AppColors.textSecondary)),
                    ]),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

class _FieldTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool muted;
  final VoidCallback onTap;

  const _FieldTile({required this.label, required this.icon, required this.muted, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade400),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(children: [
          Icon(icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Expanded(child: Text(label,
              style: TextStyle(fontSize: 14, color: muted ? AppColors.textSecondary : AppColors.textPrimary))),
          const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.textSecondary),
        ]),
      ),
    );
  }
}

class _PayChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _PayChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary.withValues(alpha: 0.1) : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? AppColors.primary : Colors.grey.shade300, width: selected ? 2 : 1),
        ),
        child: Text(label, style: TextStyle(fontWeight: FontWeight.w600,
            color: selected ? AppColors.primary : AppColors.textSecondary)),
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

  const _CustomerResult({required this.id, required this.name, required this.phone, this.email});
}

// ── Nearby vendor (from get_instahelp_vendors_by_location) ───────────────────

class _NearbyVendor {
  final String id;
  final String businessName;
  final bool isOnline;

  const _NearbyVendor({required this.id, required this.businessName, this.isOnline = false});

  @override
  bool operator ==(Object other) => other is _NearbyVendor && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
