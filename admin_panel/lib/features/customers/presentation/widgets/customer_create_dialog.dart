import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/theme/app_theme.dart';

class CustomerCreateDialog extends StatefulWidget {
  final Future<void> Function({
    required String fullName,
    required String phone,
    required String email,
    String? profileImageUrl,
    required bool isActive,
    required List<({
      String line1,
      String area,
      String city,
      String state,
      String pincode,
      String landmark,
      bool isDefault,
    })> addresses,
  }) onSave;

  const CustomerCreateDialog({super.key, required this.onSave});

  @override
  State<CustomerCreateDialog> createState() => _CustomerCreateDialogState();
}

class _AddressEntry {
  _AddressEntry()
      : line1 = TextEditingController(),
        area = TextEditingController(),
        city = TextEditingController(),
        state = TextEditingController(),
        pincode = TextEditingController(),
        landmark = TextEditingController();

  final TextEditingController line1;
  final TextEditingController area;
  final TextEditingController city;
  final TextEditingController state;
  final TextEditingController pincode;
  final TextEditingController landmark;
  bool isDefault = false;

  void dispose() {
    line1.dispose();
    area.dispose();
    city.dispose();
    state.dispose();
    pincode.dispose();
    landmark.dispose();
  }
}

class _CustomerCreateDialogState extends State<CustomerCreateDialog> {
  final _formKey = GlobalKey<FormState>();
  final _fullName = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _profileImageUrl = TextEditingController();
  bool _isActive = true;
  bool _saving = false;
  final List<_AddressEntry> _addresses = [];

  @override
  void dispose() {
    _fullName.dispose();
    _phone.dispose();
    _email.dispose();
    _profileImageUrl.dispose();
    for (final a in _addresses) {
      a.dispose();
    }
    super.dispose();
  }

  void _addAddress() {
    setState(() {
      final entry = _AddressEntry();
      // First address is default by default
      if (_addresses.isEmpty) entry.isDefault = true;
      _addresses.add(entry);
    });
  }

  void _removeAddress(int index) {
    setState(() {
      _addresses[index].dispose();
      _addresses.removeAt(index);
      // Ensure exactly one default if any remain
      if (_addresses.isNotEmpty &&
          !_addresses.any((a) => a.isDefault)) {
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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final addressList = _addresses.map((a) => (
            line1: a.line1.text.trim(),
            area: a.area.text.trim(),
            city: a.city.text.trim(),
            state: a.state.text.trim(),
            pincode: a.pincode.text.trim(),
            landmark: a.landmark.text.trim(),
            isDefault: a.isDefault,
          )).toList();

      await widget.onSave(
        fullName: _fullName.text.trim(),
        phone: _phone.text.trim(),
        email: _email.text.trim(),
        profileImageUrl: _profileImageUrl.text.trim().isEmpty
            ? null
            : _profileImageUrl.text.trim(),
        isActive: _isActive,
        addresses: addressList,
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
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header ──────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 20),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.person_add_rounded,
                      color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  const Text(
                    'New Customer',
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
                    icon: const Icon(Icons.close_rounded,
                        color: Colors.white70),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),

            // ── Form ────────────────────────────────────────────────────
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Info banner
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color:
                                  AppColors.primary.withValues(alpha: 0.2)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline_rounded,
                                size: 16, color: AppColors.primary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'This customer will be marked as Admin Created. '
                                'They can be assigned bookings and all customer data applies.',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.primary),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Full Name
                      TextFormField(
                        controller: _fullName,
                        decoration: const InputDecoration(
                          labelText: 'Full Name *',
                          hintText: 'Full Name',
                          prefixIcon: Icon(Icons.badge_rounded),
                        ),
                        textCapitalization: TextCapitalization.words,
                        validator: (v) =>
                            v == null || v.trim().isEmpty
                                ? 'Full name is required'
                                : null,
                      ),
                      const SizedBox(height: 16),

                      // Phone + Email
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _phone,
                              decoration: const InputDecoration(
                                labelText: 'Phone *',
                                hintText: 'Phone Number',
                                prefixIcon: Icon(Icons.phone_rounded),
                              ),
                              keyboardType: TextInputType.phone,
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
                                labelText: 'Email',
                                hintText: 'Email Address',
                                prefixIcon: Icon(Icons.email_rounded),
                              ),
                              keyboardType: TextInputType.emailAddress,
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) {
                                  return null;
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

                      // Profile Image URL
                      TextFormField(
                        controller: _profileImageUrl,
                        decoration: const InputDecoration(
                          labelText: 'Profile Image URL',
                          hintText: 'https://…',
                          prefixIcon: Icon(Icons.image_rounded),
                        ),
                        keyboardType: TextInputType.url,
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
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          subtitle: Text(
                            _isActive
                                ? 'Customer can be assigned bookings immediately'
                                : 'Customer account starts disabled',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          value: _isActive,
                          onChanged: (v) => setState(() => _isActive = v),
                          activeThumbColor: AppColors.success,
                        ),
                      ),

                      // ── Addresses ──────────────────────────────────────
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
                                  'Add one or more saved addresses for this customer',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          TextButton.icon(
                            onPressed: _addAddress,
                            icon: const Icon(Icons.add_rounded, size: 18),
                            label: const Text('Add Address'),
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.primary,
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                        ],
                      ),

                      if (_addresses.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AppColors.background,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: AppColors.border,
                                  style: BorderStyle.solid),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.location_off_outlined,
                                    size: 16,
                                    color: AppColors.textSecondary),
                                const SizedBox(width: 8),
                                Text(
                                  'No addresses added — customer can add them later',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                    fontStyle: FontStyle.italic,
                                  ),
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
                            canRemove: true,
                            onRemove: () => _removeAddress(i),
                            onSetDefault: () => _setDefault(i),
                          ),
                        ],
                    ],
                  ),
                ),
              ),
            ),

            // ── Footer ──────────────────────────────────────────────────
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
                  FilledButton.icon(
                    onPressed: _saving ? null : _submit,
                    icon: _saving
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.person_add_rounded, size: 16),
                    label: const Text('Create Customer'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                    ),
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

class _AddressCard extends StatefulWidget {
  final int index;
  final _AddressEntry entry;
  final bool canRemove;
  final VoidCallback onRemove;
  final VoidCallback onSetDefault;

  const _AddressCard({
    required this.index,
    required this.entry,
    required this.canRemove,
    required this.onRemove,
    required this.onSetDefault,
  });

  @override
  State<_AddressCard> createState() => _AddressCardState();
}

class _AddressCardState extends State<_AddressCard> {
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
                  padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 2),
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
              if (widget.canRemove)
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
            validator: (v) =>
                v == null || v.trim().isEmpty ? 'Address line is required' : null,
          ),
          const SizedBox(height: 10),

          // Area / Locality
          TextFormField(
            controller: widget.entry.area,
            decoration: const InputDecoration(
              labelText: 'Area / Locality',
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

          // Pincode + Landmark
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  controller: widget.entry.pincode,
                  decoration: const InputDecoration(
                    labelText: 'Pincode *',
                    isDense: true,
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Required' : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: widget.entry.landmark,
                  decoration: const InputDecoration(
                    labelText: 'Landmark',
                    hintText: 'Near school, temple…',
                    isDense: true,
                  ),
                  textCapitalization: TextCapitalization.sentences,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Default toggle
          InkWell(
            onTap: widget.entry.isDefault ? null : widget.onSetDefault,
            borderRadius: BorderRadius.circular(6),
            child: Row(
              children: [
                Icon(
                  widget.entry.isDefault
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  size: 18,
                  color: widget.entry.isDefault
                      ? AppColors.primary
                      : AppColors.textSecondary,
                ),
                const SizedBox(width: 8),
                Text(
                  widget.entry.isDefault
                      ? 'Default address'
                      : 'Set as default',
                  style: TextStyle(
                    fontSize: 13,
                    color: widget.entry.isDefault
                        ? AppColors.primary
                        : AppColors.textSecondary,
                    fontWeight: widget.entry.isDefault
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
