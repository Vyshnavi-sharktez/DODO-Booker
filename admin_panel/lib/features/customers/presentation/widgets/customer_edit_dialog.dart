import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/image_upload_field.dart';
import '../../../../core/widgets/phone_input_field.dart';
import '../../../vendors/presentation/widgets/vendor_location_picker_dialog.dart';
import '../../domain/models/customer.dart';
import '../../domain/models/customer_address.dart';

// ── Mutable address entry ──────────────────────────────────────────────────────

class _AddrEntry {
  String? id; // null = new (not yet in DB)
  final TextEditingController line1;
  final TextEditingController line2;
  final TextEditingController city;
  final TextEditingController state;
  final TextEditingController pincode;
  bool isDefault;
  double? latitude;
  double? longitude;

  _AddrEntry({
    this.id,
    String line1Init = '',
    String line2Init = '',
    String cityInit = '',
    String stateInit = '',
    String pincodeInit = '',
    this.isDefault = false,
    this.latitude,
    this.longitude,
  })  : line1 = TextEditingController(text: line1Init),
        line2 = TextEditingController(text: line2Init),
        city = TextEditingController(text: cityInit),
        state = TextEditingController(text: stateInit),
        pincode = TextEditingController(text: pincodeInit);

  factory _AddrEntry.fromAddress(CustomerAddress a) => _AddrEntry(
        id: a.id,
        line1Init: a.addressLine1,
        line2Init: a.addressLine2 ?? '',
        cityInit: a.city,
        stateInit: a.state,
        pincodeInit: a.pincode,
        isDefault: a.isDefault,
        latitude: a.latitude,
        longitude: a.longitude,
      );

  void dispose() {
    line1.dispose();
    line2.dispose();
    city.dispose();
    state.dispose();
    pincode.dispose();
  }
}

// ── Dialog ────────────────────────────────────────────────────────────────────

class CustomerEditDialog extends StatefulWidget {
  final Customer customer;
  final Future<void> Function({
    required String fullName,
    required String phone,
    required String email,
    String? profileImageUrl,
    required bool isActive,
  }) onSave;

  const CustomerEditDialog({
    super.key,
    required this.customer,
    required this.onSave,
  });

  @override
  State<CustomerEditDialog> createState() => _CustomerEditDialogState();
}

class _CustomerEditDialogState extends State<CustomerEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _fullName;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  String? _profileImageUrl;
  late bool _isActive;
  bool _saving = false;
  bool _loadingAddresses = true;

  final List<_AddrEntry> _addresses = [];
  final List<String> _deletedAddressIds = [];

  @override
  void initState() {
    super.initState();
    final c = widget.customer;
    _fullName = TextEditingController(text: c.fullName);
    final phone = c.phone;
    _phone = TextEditingController(
      text: phone.startsWith('+91') ? phone.substring(3) : phone,
    );
    _email = TextEditingController(text: c.email);
    _profileImageUrl =
        c.profileImageUrl?.isNotEmpty == true ? c.profileImageUrl : null;
    _isActive = c.isActive;
    _loadAddresses();
  }

  @override
  void dispose() {
    _fullName.dispose();
    _phone.dispose();
    _email.dispose();
    for (final a in _addresses) {
      a.dispose();
    }
    super.dispose();
  }

  Future<void> _loadAddresses() async {
    try {
      final rows = await Supabase.instance.client
          .from('customer_addresses')
          .select()
          .eq('customer_id', widget.customer.id)
          .order('is_default', ascending: false);
      if (mounted) {
        setState(() {
          for (final r in rows) {
            _addresses.add(_AddrEntry.fromAddress(
                CustomerAddress.fromMap(r)));
          }
          _loadingAddresses = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingAddresses = false);
    }
  }

  void _addAddress() {
    setState(() {
      final entry = _AddrEntry(isDefault: _addresses.isEmpty);
      _addresses.add(entry);
    });
  }

  void _removeAddress(int index) {
    setState(() {
      final entry = _addresses[index];
      if (entry.id != null) _deletedAddressIds.add(entry.id!);
      entry.dispose();
      _addresses.removeAt(index);
      if (_addresses.isNotEmpty && !_addresses.any((a) => a.isDefault)) {
        _addresses.first.isDefault = true;
      }
    });
  }

  void _setDefault(int index) {
    setState(() {
      for (var i = 0; i < _addresses.length; i++) {
        _addresses[i].isDefault = i == index;
      }
    });
  }

  Future<void> _saveAddresses() async {
    final client = Supabase.instance.client;

    // Delete removed addresses
    for (final id in _deletedAddressIds) {
      await client.from('customer_addresses').delete().eq('id', id);
    }

    for (final a in _addresses) {
      final payload = {
        'customer_id': widget.customer.id,
        'address_type': 'Home',
        'address_line_1': a.line1.text.trim(),
        'address_line_2': a.line2.text.trim().isNotEmpty
            ? a.line2.text.trim()
            : null,
        'city': a.city.text.trim(),
        'state': a.state.text.trim(),
        'pincode': a.pincode.text.trim(),
        'is_default': a.isDefault,
        if (a.latitude != null) 'latitude': a.latitude,
        if (a.longitude != null) 'longitude': a.longitude,
      };
      if (a.id != null) {
        await client
            .from('customer_addresses')
            .update(payload)
            .eq('id', a.id!);
      } else {
        await client.from('customer_addresses').insert(payload);
      }
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await widget.onSave(
        fullName: _fullName.text.trim(),
        phone: '+91${_phone.text.trim()}',
        email: _email.text.trim(),
        profileImageUrl: _profileImageUrl,
        isActive: _isActive,
      );
      await _saveAddresses();
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
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
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
                  const Text(
                    'Edit Customer',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Full Name
                      TextFormField(
                        controller: _fullName,
                        decoration: const InputDecoration(
                          labelText: 'Full Name *',
                          hintText: 'Full Name',
                          prefixIcon: Icon(Icons.badge_rounded),
                        ),
                        textCapitalization: TextCapitalization.words,
                        validator: (v) => v == null || v.trim().isEmpty
                            ? 'Full name is required'
                            : null,
                      ),
                      const SizedBox(height: 16),

                      // Phone + Email
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: PhoneInputField(
                              controller: _phone,
                              labelText: 'Phone *',
                              hintText: 'Phone Number',
                              validator: (v) =>
                                  v == null || v.trim().isEmpty
                                      ? 'Phone is required'
                                      : null,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _email,
                              decoration: const InputDecoration(
                                labelText: 'Email *',
                                hintText: 'Email Address',
                                prefixIcon: Icon(Icons.email_rounded),
                              ),
                              keyboardType: TextInputType.emailAddress,
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) {
                                  return 'Email is required';
                                }
                                if (!v.contains('@')) {
                                  return 'Enter a valid email';
                                }
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Profile Image
                      ImageUploadField(
                        label: 'Profile Image',
                        value: _profileImageUrl,
                        onChanged: (url) =>
                            setState(() => _profileImageUrl = url),
                        bucket: 'avatars',
                        pathPrefix: 'customers/',
                      ),
                      const SizedBox(height: 16),

                      // Active toggle
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.border),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: SwitchListTile(
                          title: const Text(
                            'Active',
                            style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w500),
                          ),
                          subtitle: Text(
                            _isActive
                                ? 'Customer can log in and place bookings'
                                : 'Customer account is disabled',
                            style: TextStyle(
                                fontSize: 12, color: AppColors.textSecondary),
                          ),
                          value: _isActive,
                          onChanged: (v) => setState(() => _isActive = v),
                          activeThumbColor: AppColors.success,
                        ),
                      ),

                      // ── Addresses ────────────────────────────────────────
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Addresses',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Edit, remove or add saved addresses',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          TextButton.icon(
                            onPressed: _saving ? null : _addAddress,
                            icon: const Icon(Icons.add_rounded, size: 18),
                            label: const Text('Add Address'),
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.primary,
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                        ],
                      ),

                      if (_loadingAddresses)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (_addresses.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AppColors.background,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.location_off_outlined,
                                    size: 16, color: AppColors.textSecondary),
                                const SizedBox(width: 8),
                                Text(
                                  'No addresses — customer can add them from the app',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary,
                                      fontStyle: FontStyle.italic),
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        for (var i = 0; i < _addresses.length; i++) ...[
                          const SizedBox(height: 12),
                          _AddressCard(
                            index: i,
                            entry: _addresses[i],
                            onRemove: () => _removeAddress(i),
                            onSetDefault: () => _setDefault(i),
                          ),
                        ],
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
                    onPressed: _saving ? null : _submit,
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

// ── Address card widget ────────────────────────────────────────────────────────

class _AddressCard extends StatefulWidget {
  final int index;
  final _AddrEntry entry;
  final VoidCallback onRemove;
  final VoidCallback onSetDefault;

  const _AddressCard({
    required this.index,
    required this.entry,
    required this.onRemove,
    required this.onSetDefault,
  });

  @override
  State<_AddressCard> createState() => _AddressCardState();
}

class _AddressCardState extends State<_AddressCard> {
  Future<void> _pickFromMap() async {
    final result = await showDialog<VendorLocationPickerResult>(
      context: context,
      builder: (_) => VendorLocationPickerDialog(
        initialLatitude: widget.entry.latitude,
        initialLongitude: widget.entry.longitude,
      ),
    );
    if (result != null && mounted) {
      widget.entry.latitude = result.latitude;
      widget.entry.longitude = result.longitude;
      if (result.address?.isNotEmpty == true) {
        widget.entry.line1.text = result.address!;
      }
      if (result.city?.isNotEmpty == true) {
        widget.entry.city.text = result.city!;
      }
      if (result.state?.isNotEmpty == true) {
        widget.entry.state.text = result.state!;
      }
      if (result.pincode?.isNotEmpty == true) {
        widget.entry.pincode.text = result.pincode!;
      }
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: widget.entry.isDefault
              ? AppColors.primary.withValues(alpha: 0.5)
              : AppColors.border,
          width: widget.entry.isDefault ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Card header
          Row(
            children: [
              Icon(Icons.location_on_rounded,
                  size: 15, color: AppColors.primary),
              const SizedBox(width: 6),
              Text(
                'Address ${widget.index + 1}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              if (widget.entry.isDefault) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'Default',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
              const Spacer(),
              IconButton(
                onPressed: _pickFromMap,
                icon: Icon(
                  Icons.map_outlined,
                  size: 16,
                  color: widget.entry.latitude != null
                      ? AppColors.primary
                      : AppColors.textSecondary,
                ),
                tooltip: widget.entry.latitude != null
                    ? 'Location set — re-pick on map'
                    : 'Pick on map',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 4),
              if (!widget.entry.isDefault)
                TextButton(
                  onPressed: widget.onSetDefault,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: const Text('Set Default',
                      style: TextStyle(fontSize: 11)),
                ),
              IconButton(
                onPressed: widget.onRemove,
                icon: const Icon(Icons.remove_circle_outline_rounded,
                    size: 18),
                color: AppColors.error,
                tooltip: 'Remove address',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Address Line 1
          TextFormField(
            controller: widget.entry.line1,
            decoration: const InputDecoration(
              labelText: 'Address Line *',
              hintText: 'House/Flat no., Building, Street',
              isDense: true,
            ),
            textCapitalization: TextCapitalization.sentences,
            validator: (v) => v == null || v.trim().isEmpty
                ? 'Address line is required'
                : null,
          ),
          const SizedBox(height: 10),

          // Area / Landmark
          TextFormField(
            controller: widget.entry.line2,
            decoration: const InputDecoration(
              labelText: 'Area / Landmark',
              hintText: 'Colony, Area, Locality',
              isDense: true,
            ),
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 10),

          // City + State
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  controller: widget.entry.city,
                  decoration: const InputDecoration(
                    labelText: 'City *',
                    isDense: true,
                  ),
                  textCapitalization: TextCapitalization.words,
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Required' : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: widget.entry.state,
                  decoration: const InputDecoration(
                    labelText: 'State *',
                    isDense: true,
                  ),
                  textCapitalization: TextCapitalization.words,
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Required' : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Pincode
          SizedBox(
            width: 160,
            child: TextFormField(
              controller: widget.entry.pincode,
              decoration: const InputDecoration(
                labelText: 'Pincode *',
                isDense: true,
              ),
              keyboardType: TextInputType.number,
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Required' : null,
            ),
          ),
        ],
      ),
    );
  }
}
