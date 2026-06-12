import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../auth/presentation/providers/auth_controller.dart';
import '../../domain/models/vendor_profile.dart';
import '../providers/profile_provider.dart';

class EditProfilePage extends ConsumerStatefulWidget {
  const EditProfilePage({super.key, required this.profile});
  final VendorProfile profile;

  @override
  ConsumerState<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends ConsumerState<EditProfilePage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _businessNameCtrl;
  late final TextEditingController _ownerNameCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _cityCtrl;
  late final TextEditingController _addressCtrl;

  @override
  void initState() {
    super.initState();
    _businessNameCtrl =
        TextEditingController(text: widget.profile.businessName);
    _ownerNameCtrl =
        TextEditingController(text: widget.profile.ownerName ?? '');
    _emailCtrl = TextEditingController(text: widget.profile.email ?? '');
    _cityCtrl = TextEditingController(text: widget.profile.city ?? '');
    _addressCtrl = TextEditingController(text: widget.profile.address ?? '');
  }

  @override
  void dispose() {
    _businessNameCtrl.dispose();
    _ownerNameCtrl.dispose();
    _emailCtrl.dispose();
    _cityCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final user = ref.read(currentVendorUserProvider);
    if (user == null) return;
    ref.read(editProfileProvider.notifier).save(
      phone: user.phone,
      fields: {
        'business_name': _businessNameCtrl.text.trim(),
        'owner_name': _ownerNameCtrl.text.trim(),
        'email': _emailCtrl.text.trim(),
        'city': _cityCtrl.text.trim(),
        'address': _addressCtrl.text.trim(),
        'updated_at': DateTime.now().toIso8601String(),
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<void>>(editProfileProvider, (prev, next) {
      if (next is AsyncData && prev?.isLoading == true) {
        ref.invalidate(vendorProfileProvider);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile updated successfully'),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.of(context).pop();
      } else if (next is AsyncError) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Update failed: ${next.error}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    });

    final isSaving = ref.watch(editProfileProvider).isLoading;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Profile'),
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: AbsorbPointer(
        absorbing: isSaving,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildField(
                  controller: _businessNameCtrl,
                  label: 'Business Name',
                  icon: Icons.store_outlined,
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Business name is required'
                      : null,
                ),
                const SizedBox(height: 16),
                _buildField(
                  controller: _ownerNameCtrl,
                  label: 'Owner Name',
                  icon: Icons.person_outline_rounded,
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Owner name is required'
                      : null,
                ),
                const SizedBox(height: 16),
                _buildField(
                  controller: _emailCtrl,
                  label: 'Email',
                  icon: Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                  validator: _validateEmail,
                ),
                const SizedBox(height: 16),
                _buildField(
                  controller: _cityCtrl,
                  label: 'City',
                  icon: Icons.location_city_outlined,
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'City is required'
                      : null,
                ),
                const SizedBox(height: 16),
                _buildField(
                  controller: _addressCtrl,
                  label: 'Address',
                  icon: Icons.place_outlined,
                  maxLines: 3,
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Address is required'
                      : null,
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  onPressed: isSaving ? null : _submit,
                  icon: isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(isSaving ? 'Saving…' : 'Save Changes'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      validator: validator,
      keyboardType: maxLines > 1 ? TextInputType.multiline : keyboardType,
      textInputAction:
          maxLines > 1 ? TextInputAction.newline : TextInputAction.next,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: AppColors.background,
      ),
    );
  }

  String? _validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) return 'Email is required';
    final emailRegex = RegExp(r'^[\w.+\-]+@[\w\-]+\.[a-zA-Z]{2,}$');
    if (!emailRegex.hasMatch(value.trim())) {
      return 'Enter a valid email address';
    }
    return null;
  }
}
