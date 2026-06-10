import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/models/customer.dart';

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
  late final TextEditingController _profileImageUrl;
  late bool _isActive;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final c = widget.customer;
    _fullName = TextEditingController(text: c.fullName);
    _phone = TextEditingController(text: c.phone);
    _email = TextEditingController(text: c.email);
    _profileImageUrl =
        TextEditingController(text: c.profileImageUrl ?? '');
    _isActive = c.isActive;
  }

  @override
  void dispose() {
    _fullName.dispose();
    _phone.dispose();
    _email.dispose();
    _profileImageUrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await widget.onSave(
        fullName: _fullName.text.trim(),
        phone: _phone.text.trim(),
        email: _email.text.trim(),
        profileImageUrl: _profileImageUrl.text.trim().isEmpty
            ? null
            : _profileImageUrl.text.trim(),
        isActive: _isActive,
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
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
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
                  const Icon(Icons.edit_rounded,
                      color: Colors.white, size: 20),
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
                    icon: const Icon(Icons.close_rounded,
                        color: Colors.white70),
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

                      // Profile Image URL
                      TextFormField(
                        controller: _profileImageUrl,
                        decoration: const InputDecoration(
                          labelText: 'Profile Image URL',
                          hintText: 'Profile Image URL',
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
                                ? 'Customer can log in and place bookings'
                                : 'Customer account is disabled',
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
