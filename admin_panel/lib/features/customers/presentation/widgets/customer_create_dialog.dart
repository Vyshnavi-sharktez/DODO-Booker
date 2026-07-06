import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';

class CustomerCreateDialog extends StatefulWidget {
  final Future<void> Function({
    required String fullName,
    required String phone,
    required String email,
    String? profileImageUrl,
    required bool isActive,
  }) onSave;

  const CustomerCreateDialog({super.key, required this.onSave});

  @override
  State<CustomerCreateDialog> createState() => _CustomerCreateDialogState();
}

class _CustomerCreateDialogState extends State<CustomerCreateDialog> {
  final _formKey = GlobalKey<FormState>();
  final _fullName = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _profileImageUrl = TextEditingController();
  bool _isActive = true;
  bool _saving = false;

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
      insetPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
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
