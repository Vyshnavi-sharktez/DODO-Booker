import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/services/nominatim_service.dart';
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

  double? _latitude;
  double? _longitude;
  bool _isLocating = false;
  String? _locationError;

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
    _latitude = widget.profile.latitude;
    _longitude = widget.profile.longitude;
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

  Future<void> _useCurrentLocation() async {
    setState(() {
      _isLocating = true;
      _locationError = null;
    });
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        setState(() => _locationError =
            'Location services are disabled. Please enable GPS.');
        await Geolocator.openLocationSettings();
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied) {
        setState(() => _locationError = 'Location permission denied.');
        return;
      }
      if (perm == LocationPermission.deniedForever) {
        setState(
            () => _locationError = 'Location permission permanently denied.');
        await Geolocator.openAppSettings();
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      ).timeout(const Duration(seconds: 10));
      try {
        final addr = await NominatimService()
            .reverseGeocode(pos.latitude, pos.longitude);
        if (addr.city?.isNotEmpty ?? false) {
          _cityCtrl.text = addr.city!;
        }
        if (addr.line1?.isNotEmpty ?? false) {
          _addressCtrl.text = addr.line1!;
        }
      } catch (_) {
        // Geocoding failed — coordinates still captured, fill fields manually
      }
      setState(() {
        _latitude = pos.latitude;
        _longitude = pos.longitude;
        _locationError = null;
      });
    } on TimeoutException {
      setState(() => _locationError = 'Location request timed out. Try again.');
    } on LocationServiceDisabledException {
      setState(
          () => _locationError = 'Location services are disabled. Enable GPS.');
      await Geolocator.openLocationSettings();
    } catch (_) {
      setState(() => _locationError = 'Could not get location. Try again.');
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
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
        'latitude': ?_latitude,
        'longitude': ?_longitude,
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
                const SizedBox(height: 12),

                // Use My Location
                OutlinedButton.icon(
                  onPressed:
                      (_isLocating || isSaving) ? null : _useCurrentLocation,
                  icon: _isLocating
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.my_location_rounded),
                  label: Text(_isLocating ? 'Locating…' : 'Use My Location'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
                if (_locationError != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    _locationError!,
                    style: TextStyle(fontSize: 12, color: AppColors.error),
                  ),
                ],
                if (_latitude != null && _longitude != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.location_on_rounded,
                          size: 14, color: AppColors.success),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'Pinned: ${_latitude!.toStringAsFixed(5)}, '
                          '${_longitude!.toStringAsFixed(5)}',
                          style: TextStyle(
                              fontSize: 12, color: AppColors.success),
                        ),
                      ),
                      GestureDetector(
                        onTap: () =>
                            setState(() {
                              _latitude = null;
                              _longitude = null;
                            }),
                        child: Icon(Icons.close_rounded,
                            size: 14, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ],
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
