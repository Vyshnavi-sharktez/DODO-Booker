import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/models/vendor.dart';

const _statusOptions = [
  ('pending', 'Pending'),
  ('active', 'Active'),
  ('inactive', 'Inactive'),
  ('suspended', 'Suspended'),
];

class VendorFormDialog extends StatefulWidget {
  final Vendor? existing;
  final Future<void> Function({
    required String businessName,
    String? ownerName,
    required String phone,
    required String email,
    required String city,
    String? address,
    required String status,
    required bool isActive,
    double? rating,
    double? walletBalance,
  }) onSave;

  const VendorFormDialog({
    super.key,
    this.existing,
    required this.onSave,
  });

  @override
  State<VendorFormDialog> createState() => _VendorFormDialogState();
}

class _VendorFormDialogState extends State<VendorFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _businessName;
  late final TextEditingController _ownerName;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  late final TextEditingController _city;
  late final TextEditingController _address;
  late final TextEditingController _rating;
  late final TextEditingController _walletBalance;
  late String _status;
  late bool _isActive;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _businessName = TextEditingController(text: e?.businessName ?? '');
    _ownerName = TextEditingController(text: e?.ownerName ?? '');
    _phone = TextEditingController(text: e?.phone ?? '');
    _email = TextEditingController(text: e?.email ?? '');
    _city = TextEditingController(text: e?.city ?? '');
    _address = TextEditingController(text: e?.address ?? '');
    _rating = TextEditingController(
      text: e?.rating != null ? e!.rating!.toStringAsFixed(1) : '',
    );
    _walletBalance = TextEditingController(
      text: e != null ? e.walletBalance.toStringAsFixed(2) : '',
    );
    _status = e?.status ?? 'pending';
    _isActive = e?.isActive ?? false;
  }

  @override
  void dispose() {
    _businessName.dispose();
    _ownerName.dispose();
    _phone.dispose();
    _email.dispose();
    _city.dispose();
    _address.dispose();
    _rating.dispose();
    _walletBalance.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final ratingText = _rating.text.trim();
      final walletText = _walletBalance.text.trim();
      await widget.onSave(
        businessName: _businessName.text.trim(),
        ownerName: _ownerName.text.trim().isEmpty ? null : _ownerName.text.trim(),
        phone: _phone.text.trim(),
        email: _email.text.trim(),
        city: _city.text.trim(),
        address: _address.text.trim().isEmpty ? null : _address.text.trim(),
        status: _status,
        isActive: _isActive,
        rating: ratingText.isEmpty ? null : double.tryParse(ratingText),
        walletBalance: walletText.isEmpty ? null : double.tryParse(walletText),
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
    final isEdit = widget.existing != null;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 580,
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
                  Icon(
                    isEdit
                        ? Icons.edit_rounded
                        : Icons.add_circle_outline_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    isEdit ? 'Edit Vendor' : 'New Vendor',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
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
                      // Business Name + Owner Name
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _businessName,
                              decoration: const InputDecoration(
                                labelText: 'Business Name *',
                                hintText: 'Business Name',
                                prefixIcon: Icon(Icons.store_rounded),
                              ),
                              textCapitalization: TextCapitalization.words,
                              validator: (v) =>
                                  v == null || v.trim().isEmpty ? 'Required' : null,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _ownerName,
                              decoration: const InputDecoration(
                                labelText: 'Owner Name',
                                hintText: 'Owner Name',
                                prefixIcon: Icon(Icons.person_rounded),
                                helperText: 'Optional',
                              ),
                              textCapitalization: TextCapitalization.words,
                            ),
                          ),
                        ],
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
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                    RegExp(r'[\d\+\-\s\(\)]')),
                              ],
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) {
                                  return 'Required';
                                }
                                if (v.replaceAll(RegExp(r'\D'), '').length < 10) {
                                  return 'Min 10 digits';
                                }
                                return null;
                              },
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
                                  return 'Required';
                                }
                                if (!RegExp(r'^[^@]+@[^@]+\.[^@]+')
                                    .hasMatch(v.trim())) {
                                  return 'Invalid email';
                                }
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // City + Status
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _city,
                              decoration: const InputDecoration(
                                labelText: 'City *',
                                hintText: 'City',
                                prefixIcon: Icon(Icons.location_city_rounded),
                              ),
                              textCapitalization: TextCapitalization.words,
                              validator: (v) =>
                                  v == null || v.trim().isEmpty ? 'Required' : null,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              // ignore: deprecated_member_use
                              value: _status,
                              decoration: const InputDecoration(
                                labelText: 'Status *',
                                prefixIcon: Icon(Icons.flag_rounded),
                              ),
                              items: _statusOptions
                                  .map(
                                    (s) => DropdownMenuItem(
                                      value: s.$1,
                                      child: Text(s.$2),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) {
                                if (v != null) {
                                  setState(() => _status = v);
                                }
                              },
                              validator: (v) =>
                                  v == null ? 'Required' : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Address
                      TextFormField(
                        controller: _address,
                        decoration: const InputDecoration(
                          labelText: 'Address',
                          hintText: 'Street address, area',
                          prefixIcon: Icon(Icons.place_rounded),
                        ),
                        maxLines: 2,
                        textCapitalization: TextCapitalization.sentences,
                      ),
                      const SizedBox(height: 16),

                      // Rating + Wallet Balance
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 160,
                            child: TextFormField(
                              controller: _rating,
                              decoration: const InputDecoration(
                                labelText: 'Rating',
                                hintText: 'Rating',
                                prefixIcon: Icon(Icons.star_rounded),
                                helperText: 'Optional, 0.0 – 5.0',
                              ),
                              keyboardType: const TextInputType.numberWithOptions(
                                  decimal: true),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                    RegExp(r'^\d?\.?\d?')),
                              ],
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) return null;
                                final r = double.tryParse(v.trim());
                                if (r == null || r < 0 || r > 5) {
                                  return 'Enter 0.0 – 5.0';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 16),
                          SizedBox(
                            width: 180,
                            child: TextFormField(
                              controller: _walletBalance,
                              decoration: const InputDecoration(
                                labelText: 'Wallet Balance',
                                hintText: 'Wallet Balance',
                                prefixIcon: Icon(Icons.account_balance_wallet_rounded),
                                helperText: 'Optional, defaults to 0',
                              ),
                              keyboardType: const TextInputType.numberWithOptions(
                                  decimal: true),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                    RegExp(r'^\d*\.?\d{0,2}')),
                              ],
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) return null;
                                if (double.tryParse(v.trim()) == null) {
                                  return 'Invalid amount';
                                }
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Active toggle
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Active',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w500),
                        ),
                        subtitle: const Text(
                          'Enable vendor on the platform',
                          style: TextStyle(fontSize: 12),
                        ),
                        value: _isActive,
                        onChanged: (v) => setState(() => _isActive = v),
                        dense: true,
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
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(isEdit ? 'Save Changes' : 'Add Vendor'),
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
