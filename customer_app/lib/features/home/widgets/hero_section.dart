import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/nominatim_service.dart';
import '../../address/screens/map_picker_screen.dart';
import '../../service_availability/services/serviceability_service.dart';

// ── Picked location (from search or map) ──────────────────────────────────────

class _PickedLocation {
  final double lat;
  final double lng;
  final String label;
  const _PickedLocation({required this.lat, required this.lng, required this.label});
}

// ── Availability check state machine ──────────────────────────────────────────

enum _CheckState {
  idle,
  gettingLocation,
  checkingAvailability,
  serviceable,
  notServiceable,
  permissionDenied,
  locationError,
  serviceabilityError,
}

extension _CheckStateX on _CheckState {
  bool get isLoading =>
      this == _CheckState.gettingLocation ||
      this == _CheckState.checkingAvailability;

  String get webButtonLabel {
    switch (this) {
      case _CheckState.idle:
        return 'Check Availability';
      case _CheckState.gettingLocation:
        return 'Getting location...';
      case _CheckState.checkingAvailability:
        return 'Checking availability...';
      case _CheckState.serviceable:
        return 'We serve your area!';
      default:
        return 'Try again';
    }
  }

  String get mobileButtonLabel {
    switch (this) {
      case _CheckState.idle:
        return 'Check Availability';
      case _CheckState.gettingLocation:
        return 'Getting location...';
      case _CheckState.checkingAvailability:
        return 'Checking availability...';
      case _CheckState.serviceable:
        return 'We serve your area!';
      default:
        return 'Try again';
    }
  }

  String? get statusMessage {
    switch (this) {
      case _CheckState.serviceable:
        return 'Great! We serve your area.';
      case _CheckState.notServiceable:
        return "Sorry, we don't serve your area yet.";
      case _CheckState.permissionDenied:
        return 'Location access denied. Allow location access in your browser to continue.';
      case _CheckState.locationError:
        return 'Could not get your location. Please try again.';
      case _CheckState.serviceabilityError:
        return "Couldn't verify your area. Please try again.";
      default:
        return null;
    }
  }

  bool get isSuccess => this == _CheckState.serviceable;
  bool get hasMessage => statusMessage != null;
}

// ── Widget ────────────────────────────────────────────────────────────────────

class HeroSection extends StatefulWidget {
  final VoidCallback onBookNow;
  final VoidCallback onExplore;

  const HeroSection({
    super.key,
    required this.onBookNow,
    required this.onExplore,
  });

  @override
  State<HeroSection> createState() => _HeroSectionState();
}

class _HeroSectionState extends State<HeroSection>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  _CheckState _checkState = _CheckState.idle;

  // Manually picked location (from search, map, or live GPS). Null = use GPS on check.
  double? _pickedLat;
  double? _pickedLng;
  String? _pickedLabel;

  // True while the pill's "Get Live Location" button is fetching GPS.
  bool _fetchingGps = false;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  // ── Location picker ────────────────────────────────────────────────────────

  Future<void> _openLocationPicker() async {
    if (_checkState.isLoading) return;
    final result = await showModalBottomSheet<_PickedLocation>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _LocationPickerSheet(),
    );
    if (result != null && mounted) {
      setState(() {
        _pickedLat = result.lat;
        _pickedLng = result.lng;
        _pickedLabel = result.label;
        _checkState = _CheckState.idle;
      });
    }
  }

  void _clearLocation() {
    setState(() {
      _pickedLat = null;
      _pickedLng = null;
      _pickedLabel = null;
      _checkState = _CheckState.idle;
    });
  }

  /// Fetches real-time GPS, reverse-geocodes it, and populates the location field.
  /// Does NOT run the serviceability check — just fills the pill.
  Future<void> _fetchLiveLocation() async {
    if (_fetchingGps) return;
    setState(() => _fetchingGps = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) setState(() => _fetchingGps = false);
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      ).timeout(const Duration(seconds: 10));

      String label = 'My Location';
      try {
        final addr = await NominatimService()
            .reverseGeocode(pos.latitude, pos.longitude);
        label = addr.line1 ?? addr.city ?? addr.state ?? 'My Location';
      } catch (_) {}

      if (mounted) {
        setState(() {
          _pickedLat = pos.latitude;
          _pickedLng = pos.longitude;
          _pickedLabel = label;
          _checkState = _CheckState.idle;
          _fetchingGps = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _fetchingGps = false);
    }
  }

  // ── Check availability flow ────────────────────────────────────────────────

  Future<void> _handleContinue() async {
    if (_checkState.isLoading) return;

    // ── Path A: user picked a location manually ────────────────────────────
    if (_pickedLat != null && _pickedLng != null) {
      setState(() => _checkState = _CheckState.checkingAvailability);
      await _runServiceabilityCheck(_pickedLat!, _pickedLng!);
      return;
    }

    // ── Path B: use real-time GPS ──────────────────────────────────────────
    setState(() => _checkState = _CheckState.gettingLocation);

    // 1. GPS service enabled?
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) setState(() => _checkState = _CheckState.locationError);
        return;
      }
    } catch (_) {
      if (mounted) setState(() => _checkState = _CheckState.locationError);
      return;
    }

    // 2. Permission check / request
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) setState(() => _checkState = _CheckState.permissionDenied);
        return;
      }
    } catch (_) {
      if (mounted) setState(() => _checkState = _CheckState.permissionDenied);
      return;
    }

    // 3. Get current position (10-second hard timeout)
    double lat, lng;
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      ).timeout(const Duration(seconds: 10));
      lat = pos.latitude;
      lng = pos.longitude;
    } on TimeoutException {
      if (mounted) setState(() => _checkState = _CheckState.locationError);
      return;
    } on LocationServiceDisabledException {
      if (mounted) setState(() => _checkState = _CheckState.locationError);
      return;
    } catch (_) {
      if (mounted) setState(() => _checkState = _CheckState.locationError);
      return;
    }

    if (!mounted) return;
    setState(() => _checkState = _CheckState.checkingAvailability);
    await _runServiceabilityCheck(lat, lng);
  }

  Future<void> _runServiceabilityCheck(double lat, double lng) async {
    final result = await ServiceabilityService().check(lat, lng);
    if (!mounted) return;

    if (result == ServiceabilityResult.serviceable) {
      setState(() => _checkState = _CheckState.serviceable);
    } else if (result == ServiceabilityResult.notServiceable) {
      setState(() => _checkState = _CheckState.notServiceable);
    } else {
      setState(() => _checkState = _CheckState.serviceabilityError);
    }
  }

  void _resetCheck() => setState(() => _checkState = _CheckState.idle);

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return FadeTransition(
      opacity: _fadeAnim,
      child: width >= 768
          ? _WebHero(
              checkState: _checkState,
              pickedLabel: _pickedLabel,
              fetchingGps: _fetchingGps,
              onContinue: _handleContinue,
              onReset: _resetCheck,
              onLocationTap: _openLocationPicker,
              onClearLocation: _clearLocation,
              onFetchLiveLocation: _fetchLiveLocation,
            )
          : _MobileHero(
              checkState: _checkState,
              onGetStarted: _handleContinue,
              onReset: _resetCheck,
            ),
    );
  }
}

// ── Web Hero ─────────────────────────────────────────────────────────────────

class _WebHero extends StatelessWidget {
  final _CheckState checkState;
  final String? pickedLabel;
  final bool fetchingGps;
  final VoidCallback onContinue;
  final VoidCallback onReset;
  final VoidCallback onLocationTap;
  final VoidCallback onClearLocation;
  final VoidCallback onFetchLiveLocation;

  const _WebHero({
    required this.checkState,
    required this.pickedLabel,
    required this.fetchingGps,
    required this.onContinue,
    required this.onReset,
    required this.onLocationTap,
    required this.onClearLocation,
    required this.onFetchLiveLocation,
  });

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final hPad = w >= 1024 ? 80.0 : 40.0;

    return Container(
      width: double.infinity,
      color: const Color(0xFF111111),
      padding: const EdgeInsets.symmetric(vertical: 72),
      child: Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: hPad),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1120),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  flex: 55,
                  child: _WebContent(
                    checkState: checkState,
                    pickedLabel: pickedLabel,
                    fetchingGps: fetchingGps,
                    onContinue: onContinue,
                    onReset: onReset,
                    onLocationTap: onLocationTap,
                    onClearLocation: onClearLocation,
                    onFetchLiveLocation: onFetchLiveLocation,
                  ),
                ),
                const SizedBox(width: 48),
                Expanded(
                  flex: 45,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 360),
                      child: Image.asset(
                        'assets/images/dodo-mascot.png',
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WebContent extends StatelessWidget {
  final _CheckState checkState;
  final String? pickedLabel;
  final bool fetchingGps;
  final VoidCallback onContinue;
  final VoidCallback onReset;
  final VoidCallback onLocationTap;
  final VoidCallback onClearLocation;
  final VoidCallback onFetchLiveLocation;

  const _WebContent({
    required this.checkState,
    required this.pickedLabel,
    required this.fetchingGps,
    required this.onContinue,
    required this.onReset,
    required this.onLocationTap,
    required this.onClearLocation,
    required this.onFetchLiveLocation,
  });

  @override
  Widget build(BuildContext context) {
    final hasLocation = pickedLabel != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Trust badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1B17),
            borderRadius: BorderRadius.circular(100),
          ),
          child: Text(
            '✓ Trusted Home Services',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.gold,
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Headline
        Text.rich(
          TextSpan(
            style: GoogleFonts.poppins(
              fontSize: 44,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              height: 1.12,
              letterSpacing: -0.5,
            ),
            children: const [
              TextSpan(text: 'Are you looking for\n'),
              TextSpan(
                text: 'home services?',
                style: TextStyle(color: AppColors.gold),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Body
        Text(
          'Let us take care of it. Book a trusted professional in just a few taps.',
          style: GoogleFonts.inter(
            fontSize: 15,
            color: const Color(0xFFB3ADA3),
            height: 1.6,
          ),
        ),
        const SizedBox(height: 8),

        // Hint
        Text(
          hasLocation
              ? 'Location set — click Check Availability to confirm service.'
              : "We'll show services for your location",
          style: GoogleFonts.inter(
            fontSize: 13,
            color: hasLocation
                ? AppColors.gold.withAlpha(200)
                : const Color(0xFF7A756D),
          ),
        ),
        const SizedBox(height: 20),

        // ── Location input pill (tappable) ──────────────────────────────────
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: MouseRegion(
            cursor: checkState.isLoading
                ? SystemMouseCursors.basic
                : SystemMouseCursors.click,
            child: GestureDetector(
              onTap: checkState.isLoading ? null : onLocationTap,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: EdgeInsets.only(
                  left: 20,
                  right: hasLocation ? 8 : 20,
                  top: 14,
                  bottom: 14,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(100),
                  border: hasLocation
                      ? Border.all(color: AppColors.gold, width: 1.5)
                      : null,
                ),
                child: Row(
                  children: [
                    Icon(
                      hasLocation
                          ? Icons.location_on_rounded
                          : Icons.location_on_outlined,
                      size: 16,
                      color: hasLocation
                          ? AppColors.primary
                          : const Color(0xFF9A948C),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        pickedLabel ??
                            'Enter your location or select from map',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: hasLocation
                              ? AppColors.textPrimary
                              : const Color(0xFF9A948C),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    if (hasLocation)
                      // Clear button
                      GestureDetector(
                        onTap: onClearLocation,
                        behavior: HitTestBehavior.opaque,
                        child: Padding(
                          padding: const EdgeInsets.all(5),
                          child: Icon(
                            Icons.close_rounded,
                            size: 15,
                            color: const Color(0xFF9A948C),
                          ),
                        ),
                      )
                    else
                      // Get Live Location button
                      GestureDetector(
                        onTap: fetchingGps ? null : onFetchLiveLocation,
                        behavior: HitTestBehavior.opaque,
                        child: Tooltip(
                          message: 'Get live GPS location',
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: const BoxDecoration(
                              color: Color(0xFFF5F2EE),
                              shape: BoxShape.circle,
                            ),
                            child: fetchingGps
                                ? const Padding(
                                    padding: EdgeInsets.all(6),
                                    child: CircularProgressIndicator(
                                      strokeWidth: 1.5,
                                      color: AppColors.primary,
                                    ),
                                  )
                                : const Icon(
                                    Icons.my_location_rounded,
                                    size: 14,
                                    color: AppColors.primary,
                                  ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),

        // Status message (shown when a result is available)
        if (checkState.hasMessage) ...[
          _StatusMessage(checkState: checkState),
          const SizedBox(height: 10),
        ],

        // Check Availability CTA
        _ContinueButton(
          checkState: checkState,
          onTap: onContinue,
          onReset: onReset,
        ),
      ],
    );
  }
}

// ── Continue button ───────────────────────────────────────────────────────────

class _ContinueButton extends StatefulWidget {
  final _CheckState checkState;
  final VoidCallback onTap;
  final VoidCallback onReset;

  const _ContinueButton({
    required this.checkState,
    required this.onTap,
    required this.onReset,
  });

  @override
  State<_ContinueButton> createState() => _ContinueButtonState();
}

class _ContinueButtonState extends State<_ContinueButton> {
  bool _hovered = false;

  VoidCallback? get _effectiveTap {
    if (widget.checkState.isLoading || widget.checkState.isSuccess) return null;
    if (widget.checkState == _CheckState.idle) return widget.onTap;
    return widget.onReset;
  }

  @override
  Widget build(BuildContext context) {
    final isActive = _effectiveTap != null && !widget.checkState.isLoading;

    return MouseRegion(
      cursor: isActive ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) {
        if (isActive) setState(() => _hovered = true);
      },
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: _effectiveTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
          decoration: BoxDecoration(
            color: _hovered && isActive
                ? const Color(0xFF2A2622)
                : const Color(0xFF1E1B17),
            borderRadius: BorderRadius.circular(100),
            border: Border.all(color: const Color(0xFF2A2622)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.checkState.isLoading) ...[
                const SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Text(
                widget.checkState.webButtonLabel,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withAlpha(
                    widget.checkState.isLoading ? 180 : 255,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Status message row ────────────────────────────────────────────────────────

class _StatusMessage extends StatelessWidget {
  final _CheckState checkState;
  const _StatusMessage({required this.checkState});

  @override
  Widget build(BuildContext context) {
    final message = checkState.statusMessage;
    if (message == null) return const SizedBox.shrink();

    final isSuccess = checkState.isSuccess;
    final color =
        isSuccess ? const Color(0xFF4ADE80) : const Color(0xFFFCA5A5);
    final icon =
        isSuccess ? Icons.check_circle_rounded : Icons.info_outline_rounded;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            message,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: color,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Location picker bottom sheet ──────────────────────────────────────────────

class _LocationPickerSheet extends StatefulWidget {
  const _LocationPickerSheet();

  @override
  State<_LocationPickerSheet> createState() => _LocationPickerSheetState();
}

class _LocationPickerSheetState extends State<_LocationPickerSheet> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  List<NominatimSearchResult> _results = [];
  bool _searching = false;
  bool _fetchingGps = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() {
        _results = [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 600), () async {
      final results = await NominatimService().search(value.trim());
      if (mounted) {
        setState(() {
          _results = results;
          _searching = false;
        });
      }
    });
  }

  Future<void> _useMyLocation() async {
    if (_fetchingGps) return;
    setState(() => _fetchingGps = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) setState(() => _fetchingGps = false);
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      ).timeout(const Duration(seconds: 10));

      String label = 'My Location';
      try {
        final addr = await NominatimService()
            .reverseGeocode(pos.latitude, pos.longitude);
        label = addr.line1 ?? addr.city ?? addr.state ?? 'My Location';
      } catch (_) {}

      if (mounted) {
        Navigator.of(context).pop(_PickedLocation(
          lat: pos.latitude,
          lng: pos.longitude,
          label: label,
        ));
      }
    } catch (_) {
      if (mounted) setState(() => _fetchingGps = false);
    }
  }

  void _selectResult(NominatimSearchResult r) {
    Navigator.of(context).pop(_PickedLocation(
      lat: r.latitude,
      lng: r.longitude,
      label: r.shortLabel,
    ));
  }

  Future<void> _openMap() async {
    final result = await Navigator.of(context).push<MapPickerResult>(
      MaterialPageRoute(builder: (_) => const MapPickerScreen()),
    );
    if (result != null && mounted) {
      final label =
          result.line1 ?? result.city ?? 'Selected location';
      Navigator.of(context).pop(_PickedLocation(
        lat: result.latitude,
        lng: result.longitude,
        label: label,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.of(context).size.height * 0.80;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Drag handle
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 8),
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFDDD8D2),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),

              // Header row
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 16, 12),
                child: Row(
                  children: [
                    Text(
                      'Choose a location',
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    // Pick on Map CTA
                    TextButton.icon(
                      onPressed: _openMap,
                      icon: const Icon(Icons.map_outlined, size: 16),
                      label: const Text('Map'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        textStyle: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                      ),
                    ),
                  ],
                ),
              ),

              // Search field
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F2EE),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: TextField(
                    controller: _ctrl,
                    focusNode: _focus,
                    onChanged: _onChanged,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: AppColors.textPrimary,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Search city, area or address…',
                      hintStyle: GoogleFonts.inter(
                        fontSize: 14,
                        color: AppColors.textHint,
                      ),
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        size: 20,
                        color: Color(0xFF9A948C),
                      ),
                      suffixIcon: _searching
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                  color: AppColors.primary,
                                ),
                              ),
                            )
                          : _ctrl.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.close_rounded,
                                      size: 18),
                                  onPressed: () {
                                    _ctrl.clear();
                                    _onChanged('');
                                  },
                                )
                              : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 14),
                    ),
                  ),
                ),
              ),

              const Divider(height: 1),

              // "Use my location" — always visible option
              ListTile(
                onTap: _fetchingGps ? null : _useMyLocation,
                leading: Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(
                    color: Color(0xFFE8F4FD),
                    shape: BoxShape.circle,
                  ),
                  child: _fetchingGps
                      ? const Padding(
                          padding: EdgeInsets.all(9),
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: Color(0xFF1A73E8),
                          ),
                        )
                      : const Icon(
                          Icons.my_location_rounded,
                          size: 18,
                          color: Color(0xFF1A73E8),
                        ),
                ),
                title: Text(
                  'Get Live Location',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                subtitle: Text(
                  'Use your current GPS location',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              const Divider(height: 1),

              // Search results list
              Flexible(
                child: _results.isEmpty && !_searching
                    ? Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: 32, horizontal: 20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.location_on_outlined,
                                size: 36,
                                color: const Color(0xFFDDD8D2)),
                            const SizedBox(height: 12),
                            Text(
                              _ctrl.text.isEmpty
                                  ? 'Type to search for a location'
                                  : 'No results found',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: AppColors.textSecondary,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: _results.length,
                        separatorBuilder: (_, _) =>
                            const Divider(height: 1, indent: 52),
                        itemBuilder: (_, i) {
                          final r = _results[i];
                          final parts = r.displayName.split(', ');
                          final title = parts.first;
                          final subtitle = parts.length > 1
                              ? parts.skip(1).take(2).join(', ')
                              : null;
                          return ListTile(
                            leading: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: const Color(0xFFF5F2EE),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.location_on_outlined,
                                size: 18,
                                color: AppColors.primary,
                              ),
                            ),
                            title: Text(
                              title,
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: subtitle != null
                                ? Text(
                                    subtitle,
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: AppColors.textSecondary,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  )
                                : null,
                            onTap: () => _selectResult(r),
                          );
                        },
                      ),
              ),

              SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Mobile Hero ──────────────────────────────────────────────────────────────

class _MobileHero extends StatelessWidget {
  final _CheckState checkState;
  final VoidCallback onGetStarted;
  final VoidCallback onReset;

  const _MobileHero({
    required this.checkState,
    required this.onGetStarted,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFF111111),
      child: Stack(
        children: [
          // Watermark "SERV / ICE" in the background
          Positioned(
            top: 20,
            left: 20,
            child: IgnorePointer(
              child: Text(
                'SERV\nICE',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w800,
                  fontSize: 72,
                  color: const Color(0xFF1E1B17),
                  height: 0.95,
                  letterSpacing: -1.5,
                ),
              ),
            ),
          ),

          // Main content column
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 36),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Logo row
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: AppColors.gold,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'DODO BOOKER',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Mascot
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: 280,
                      maxHeight: 220,
                    ),
                    child: Image.asset(
                      'assets/images/dodo-mascot.png',
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) =>
                          const SizedBox(height: 180),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Headline
                Text.rich(
                  TextSpan(
                    style: GoogleFonts.poppins(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      height: 1.15,
                    ),
                    children: const [
                      TextSpan(text: 'Are you looking for\n'),
                      TextSpan(
                        text: 'home services?',
                        style: TextStyle(color: AppColors.gold),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),

                // Body
                Text(
                  'Let us take care of it. Book trusted professionals in just a few taps.',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: const Color(0xFFB3ADA3),
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 28),

                // Check Availability pill
                _GetStartedButton(
                  checkState: checkState,
                  onTap: onGetStarted,
                  onReset: onReset,
                ),

                // Status message below button
                if (checkState.hasMessage) ...[
                  const SizedBox(height: 14),
                  _StatusMessage(checkState: checkState),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GetStartedButton extends StatelessWidget {
  final _CheckState checkState;
  final VoidCallback onTap;
  final VoidCallback onReset;

  const _GetStartedButton({
    required this.checkState,
    required this.onTap,
    required this.onReset,
  });

  VoidCallback get _effectiveTap {
    if (checkState.isLoading || checkState.isSuccess) return () {};
    if (checkState == _CheckState.idle) return onTap;
    return onReset;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _effectiveTap,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(100),
        ),
        padding: const EdgeInsets.only(left: 26, right: 5, top: 5, bottom: 5),
        child: Row(
          children: [
            Expanded(
              child: checkState.isLoading
                  ? Row(
                      children: [
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              AppColors.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            checkState.mobileButtonLabel,
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    )
                  : Text(
                      checkState.mobileButtonLabel,
                      style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
            ),
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(100),
              ),
              child: Icon(
                checkState.isLoading
                    ? Icons.hourglass_top_rounded
                    : checkState.isSuccess
                        ? Icons.check_rounded
                        : Icons.arrow_forward_rounded,
                color: AppColors.gold,
                size: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
