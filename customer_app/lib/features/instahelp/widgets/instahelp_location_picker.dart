import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/page_sheet.dart';
import '../../../models/address_model.dart';
import '../../address/screens/address_screen.dart';
import '../../address/screens/map_picker_screen.dart';

typedef IHLatLng = ({double lat, double lng});

class InstaHelpLocationPicker {
  static Future<IHLatLng?> show(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 768;
    if (isWide) {
      return showDialog<IHLatLng>(
        context: context,
        builder: (ctx) => Dialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20)),
          child: SizedBox(
            width: 420,
            child: _LocationPickerContent(
              onResult: (r) => Navigator.of(ctx).pop(r),
            ),
          ),
        ),
      ).then((v) => v);
    }
    return showModalBottomSheet<IHLatLng>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _LocationPickerContent(
        onResult: (r) => Navigator.of(ctx).pop(r),
      ),
    );
  }
}

class _LocationPickerContent extends StatefulWidget {
  final void Function(IHLatLng?) onResult;
  const _LocationPickerContent({required this.onResult});

  @override
  State<_LocationPickerContent> createState() =>
      _LocationPickerContentState();
}

class _LocationPickerContentState extends State<_LocationPickerContent> {
  bool _locating = false;
  String? _error;

  // ── GPS ────────────────────────────────────────────────────────────────────

  Future<void> _useGps() async {
    setState(() {
      _locating = true;
      _error = null;
    });
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever) {
        if (!mounted) return;
        await Geolocator.openAppSettings();
        setState(() => _locating = false);
        return;
      }
      if (perm == LocationPermission.denied) {
        setState(() {
          _error = 'Location permission denied. Please enable it in settings.';
          _locating = false;
        });
        return;
      }
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return;
        await Geolocator.openLocationSettings();
        setState(() => _locating = false);
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      ).timeout(const Duration(seconds: 12));
      if (!mounted) return;
      widget.onResult((lat: pos.latitude, lng: pos.longitude));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to get your location. Please try again.';
        _locating = false;
      });
    }
  }

  // ── Map picker — shown as bottom sheet (mobile) or dialog (desktop) ────────

  Future<void> _pickOnMap() async {
    if (!mounted) return;
    final isWide = MediaQuery.sizeOf(context).width >= 768;
    MapPickerResult? result;

    if (isWide) {
      result = await showDialog<MapPickerResult>(
        context: context,
        builder: (ctx) => Dialog(
          insetPadding: const EdgeInsets.all(24),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          child: SizedBox(
            width: 700,
            height: MediaQuery.of(ctx).size.height * 0.75,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: const MapPickerScreen(),
            ),
          ),
        ),
      );
    } else {
      result = await showModalBottomSheet<MapPickerResult>(
        context: context,
        isScrollControlled: true,
        isDismissible: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.92,
          child: ClipRRect(
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
            child: const MapPickerScreen(),
          ),
        ),
      );
    }

    if (result != null && mounted) {
      widget.onResult((lat: result.latitude, lng: result.longitude));
    }
  }

  // ── Saved addresses dialog ─────────────────────────────────────────────────

  Future<void> _pickSavedAddress() async {
    if (!mounted) return;
    final AddressModel? address = await PageSheet.show<AddressModel>(
      context,
      title: 'Select Address',
      child: const AddressScreen(inModal: true, pickMode: true),
    );
    if (address == null || !mounted) return;
    final lat = address.latitude;
    final lng = address.longitude;
    if (lat == null || lng == null) {
      setState(() {
        _error =
            'This address has no location coordinates. Edit it to add a map pin.';
      });
      return;
    }
    widget.onResult((lat: lat, lng: lng));
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(24, 20, 24, 24 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Select Your Location',
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            'We\'ll show vendors available near you',
            style: GoogleFonts.inter(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),

          // Option 1: GPS
          _LocationOption(
            icon: Icons.my_location_rounded,
            iconColor: AppColors.primary,
            iconBg: AppColors.primaryLight,
            title: 'Use Current Location',
            subtitle: 'Automatically detect via GPS',
            isLoading: _locating,
            onTap: _locating ? null : _useGps,
          ),
          const SizedBox(height: 10),

          // Option 2: Map (opens as modal, not full page)
          _LocationOption(
            icon: Icons.map_rounded,
            iconColor: const Color(0xFF0284C7),
            iconBg: const Color(0xFFE0F2FE),
            title: 'Choose on Map',
            subtitle: 'Pin your exact location on the map',
            onTap: _locating ? null : _pickOnMap,
          ),
          const SizedBox(height: 10),

          // Option 3: Saved Addresses
          _LocationOption(
            icon: Icons.bookmark_rounded,
            iconColor: const Color(0xFF7C3AED),
            iconBg: const Color(0xFFEDE9FE),
            title: 'Saved Addresses',
            subtitle: 'Pick from your saved locations',
            onTap: _locating ? null : _pickSavedAddress,
          ),

          if (_error != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: AppColors.error.withValues(alpha: 0.3)),
              ),
              child: Text(
                _error!,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: AppColors.error,
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _LocationOption extends StatefulWidget {
  const _LocationOption({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.isLoading = false,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool isLoading;

  @override
  State<_LocationOption> createState() => _LocationOptionState();
}

class _LocationOptionState extends State<_LocationOption> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.onTap != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color:
                _hovered ? AppColors.background : AppColors.surface,
            border: Border.all(
              color: _hovered
                  ? AppColors.primary.withValues(alpha: 0.4)
                  : AppColors.border,
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: _hovered
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : [],
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: widget.iconBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: widget.isLoading
                    ? const Padding(
                        padding: EdgeInsets.all(11),
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5),
                      )
                    : Icon(widget.icon,
                        size: 22, color: widget.iconColor),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.title,
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      widget.subtitle,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textHint,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
