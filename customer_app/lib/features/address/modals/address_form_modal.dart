import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/nominatim_service.dart';
import '../../../core/widgets/app_modal_dialog.dart';
import '../../../models/address_model.dart';
import '../screens/map_picker_screen.dart';
import '../services/address_providers.dart';

/// Add or edit an address. Pops with the saved [AddressModel] on success.
/// Pass [initialAddress] to enter edit mode.
class AddressFormModal extends ConsumerStatefulWidget {
  final AddressModel? initialAddress;

  const AddressFormModal({super.key, this.initialAddress});

  @override
  ConsumerState<AddressFormModal> createState() => _AddressFormModalState();
}

class _AddressFormModalState extends ConsumerState<AddressFormModal> {
  final _formKey = GlobalKey<FormState>();

  late String _label;
  final _line1Ctrl = TextEditingController();
  final _line2Ctrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _stateCtrl = TextEditingController();
  final _pincodeCtrl = TextEditingController();

  double? _latitude;
  double? _longitude;

  bool _isLoading = false;
  bool _isLocating = false;
  String? _error;
  String? _locationError;
  Future<void> Function()? _settingsCallback;

  static const _types = ['Home', 'Office', 'Other'];

  bool get _isEditing => widget.initialAddress != null;
  bool get _hasCoordinates => _latitude != null && _longitude != null;

  @override
  void initState() {
    super.initState();
    final a = widget.initialAddress;
    _label = a?.label ?? 'Home';
    _line1Ctrl.text = a?.line1 ?? '';
    _line2Ctrl.text = a?.line2 ?? '';
    _cityCtrl.text = a?.city ?? '';
    _stateCtrl.text = a?.state ?? '';
    _pincodeCtrl.text = a?.pincode ?? '';
    _latitude = a?.latitude;
    _longitude = a?.longitude;
  }

  @override
  void dispose() {
    _line1Ctrl.dispose();
    _line2Ctrl.dispose();
    _cityCtrl.dispose();
    _stateCtrl.dispose();
    _pincodeCtrl.dispose();
    super.dispose();
  }

  void _setLocationError(String msg, {Future<void> Function()? openSettings}) {
    if (!mounted) return;
    setState(() {
      _locationError = msg;
      _settingsCallback = openSettings;
      _isLocating = false;
    });
  }

  Future<void> _useCurrentLocation() async {
    setState(() {
      _isLocating = true;
      _locationError = null;
      _settingsCallback = null;
    });
    try {
      // 1. GPS service check
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _setLocationError(
          'Location services are off. Please enable GPS.',
          openSettings:
              kIsWeb ? null : () async { await Geolocator.openLocationSettings(); },
        );
        return;
      }

      // 2. Permission check / request
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        _setLocationError('Location access denied. Tap to try again.');
        return;
      }
      if (permission == LocationPermission.deniedForever) {
        if (kIsWeb) {
          _setLocationError(
            'Location blocked in browser. Click the lock icon in the address bar to allow it.',
          );
        } else {
          _setLocationError(
            'Location blocked in app settings.',
            openSettings: () async { await Geolocator.openAppSettings(); },
          );
        }
        return;
      }

      // 3. Get position (10-second hard timeout)
      final pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      ).timeout(const Duration(seconds: 10));

      if (!mounted) return;
      setState(() {
        _latitude = pos.latitude;
        _longitude = pos.longitude;
        _locationError = null;
      });

      // 4. Reverse geocode — best-effort; never blocks saving
      try {
        final addr = await NominatimService()
            .reverseGeocode(pos.latitude, pos.longitude);
        if (!mounted) return;
        setState(() {
          if (addr.line1?.isNotEmpty ?? false) _line1Ctrl.text = addr.line1!;
          if (addr.city?.isNotEmpty ?? false) _cityCtrl.text = addr.city!;
          if (addr.state?.isNotEmpty ?? false) _stateCtrl.text = addr.state!;
          if (addr.pincode?.isNotEmpty ?? false) {
            _pincodeCtrl.text = addr.pincode!;
          }
        });
      } catch (_) {
        // Coordinates are pinned; address fields stay blank for manual entry
      }
    } on TimeoutException {
      _setLocationError('Location timed out. Please try again.');
    } on LocationServiceDisabledException {
      _setLocationError(
        'Location services are off. Please enable GPS.',
        openSettings:
            kIsWeb ? null : () async { await Geolocator.openLocationSettings(); },
      );
    } catch (_) {
      _setLocationError('Could not get location. Check GPS and connectivity.');
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  Future<void> _pickOnMap() async {
    final result = await Navigator.of(context).push<MapPickerResult>(
      MaterialPageRoute(
        builder: (_) => MapPickerScreen(
          initialLatitude: _latitude,
          initialLongitude: _longitude,
        ),
        fullscreenDialog: true,
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _locationError = null;
      _latitude = result.latitude;
      _longitude = result.longitude;
      if (result.line1?.isNotEmpty ?? false) _line1Ctrl.text = result.line1!;
      if (result.city?.isNotEmpty ?? false) _cityCtrl.text = result.city!;
      if (result.state?.isNotEmpty ?? false) _stateCtrl.text = result.state!;
      if (result.pincode?.isNotEmpty ?? false) {
        _pincodeCtrl.text = result.pincode!;
      }
    });
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final AddressModel saved;
      if (_isEditing) {
        saved = await ref.read(addressNotifierProvider.notifier).update(
              widget.initialAddress!.id,
              addressType: _label,
              addressLine1: _line1Ctrl.text.trim(),
              addressLine2: _line2Ctrl.text.trim().isEmpty
                  ? null
                  : _line2Ctrl.text.trim(),
              city: _cityCtrl.text.trim(),
              province: _stateCtrl.text.trim(),
              pincode: _pincodeCtrl.text.trim(),
              latitude: _latitude,
              longitude: _longitude,
            );
      } else {
        saved = await ref.read(addressNotifierProvider.notifier).create(
              addressType: _label,
              addressLine1: _line1Ctrl.text.trim(),
              addressLine2: _line2Ctrl.text.trim().isEmpty
                  ? null
                  : _line2Ctrl.text.trim(),
              city: _cityCtrl.text.trim(),
              province: _stateCtrl.text.trim(),
              pincode: _pincodeCtrl.text.trim(),
              latitude: _latitude,
              longitude: _longitude,
            );
      }
      if (!mounted) return;
      Navigator.of(context).pop(saved);
    } catch (e) {
      if (!mounted) return;
      final message = e.toString().replaceFirst('Exception: ', '');
      setState(() {
        _isLoading = false;
        _error = message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return AppModalDialog(
      title: _isEditing ? 'Edit Address' : 'Add Address',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 4),

            // ── Location buttons ───────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: (_isLocating || _isLoading)
                        ? null
                        : _useCurrentLocation,
                    icon: _isLocating
                        ? const SizedBox.square(
                            dimension: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(AppColors.primary),
                            ),
                          )
                        : const Icon(Icons.my_location, size: 16),
                    label: const Text(
                      'Use My Location',
                      style: TextStyle(fontSize: 13),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: const BorderSide(color: AppColors.border),
                      foregroundColor: AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isLoading ? null : _pickOnMap,
                    icon: const Icon(Icons.map_outlined, size: 16),
                    label: const Text(
                      'Pick on Map',
                      style: TextStyle(fontSize: 13),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: const BorderSide(color: AppColors.border),
                      foregroundColor: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),

            // ── Location error ─────────────────────────────────────────────────
            if (_locationError != null) ...[
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      _locationError!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.error,
                      ),
                    ),
                  ),
                  if (_settingsCallback != null) ...[
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _settingsCallback,
                      child: const Text(
                        'Open Settings',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.underline,
                          decorationColor: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],

            // ── Location pinned indicator ──────────────────────────────────────
            if (_hasCoordinates) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.check_circle_outline_rounded,
                      size: 13, color: Color(0xFF2E7D32)),
                  const SizedBox(width: 4),
                  Text(
                    'Location pinned  '
                    '(${_latitude!.toStringAsFixed(5)}, ${_longitude!.toStringAsFixed(5)})',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF2E7D32),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 14),

            // ── "or fill manually" divider ─────────────────────────────────────
            Row(
              children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    'or fill manually',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary.withValues(alpha: 0.7),
                    ),
                  ),
                ),
                const Expanded(child: Divider()),
              ],
            ),

            const SizedBox(height: 14),

            // ── Address type ───────────────────────────────────────────────────
            Text('Address Type', style: _labelStyle(tt)),
            const SizedBox(height: 8),
            Row(
              children: _types.map((type) {
                final selected = _label == type;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(type),
                    selected: selected,
                    onSelected: (_) => setState(() => _label = type),
                    selectedColor: AppColors.primary.withAlpha(25),
                    labelStyle: TextStyle(
                      color:
                          selected ? AppColors.primary : AppColors.textSecondary,
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                    side: BorderSide(
                      color: selected ? AppColors.primary : AppColors.border,
                      width: selected ? 1.5 : 1,
                    ),
                    backgroundColor: AppColors.surface,
                    showCheckmark: false,
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 16),

            // ── House / Flat No., Street & Area ───────────────────────────────
            Text('House / Flat No., Street & Area', style: _labelStyle(tt)),
            const SizedBox(height: 6),
            TextFormField(
              controller: _line1Ctrl,
              decoration:
                  _inputDecoration('e.g. 204, Sunrise Apartments, MG Road'),
              validator: (v) =>
                  (v?.trim().isEmpty ?? true) ? 'Required' : null,
            ),

            const SizedBox(height: 14),

            // ── Landmark ──────────────────────────────────────────────────────
            Text('Landmark (Optional)', style: _labelStyle(tt)),
            const SizedBox(height: 6),
            TextFormField(
              controller: _line2Ctrl,
              decoration: _inputDecoration('e.g. Near City Mall'),
            ),

            const SizedBox(height: 14),

            // ── City & State row ───────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('City', style: _labelStyle(tt)),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _cityCtrl,
                        decoration: _inputDecoration('e.g. Bengaluru'),
                        textCapitalization: TextCapitalization.words,
                        validator: (v) =>
                            (v?.trim().isEmpty ?? true) ? 'Required' : null,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('State', style: _labelStyle(tt)),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _stateCtrl,
                        decoration: _inputDecoration('e.g. Karnataka'),
                        textCapitalization: TextCapitalization.words,
                        validator: (v) =>
                            (v?.trim().isEmpty ?? true) ? 'Required' : null,
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),

            // ── Pincode ────────────────────────────────────────────────────────
            Text('Pincode', style: _labelStyle(tt)),
            const SizedBox(height: 6),
            TextFormField(
              controller: _pincodeCtrl,
              decoration: _inputDecoration('e.g. 560001'),
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Required';
                if (v.trim().length != 6) return '6 digits required';
                return null;
              },
            ),

            // ── Save error ─────────────────────────────────────────────────────
            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.error.withAlpha(18),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _error!,
                  style:
                      const TextStyle(fontSize: 13, color: AppColors.error),
                  textAlign: TextAlign.center,
                ),
              ),
            ],

            const SizedBox(height: 24),

            FilledButton(
              onPressed: _isLoading ? null : _save,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              child: _isLoading
                  ? const SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      _isEditing ? 'Update Address' : 'Save Address',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  TextStyle? _labelStyle(TextTheme tt) => tt.labelMedium?.copyWith(
        fontWeight: FontWeight.w600,
        color: AppColors.textSecondary,
      );

  InputDecoration _inputDecoration(String hint) => InputDecoration(
        hintText: hint,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: AppColors.error, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        isDense: true,
      );
}
