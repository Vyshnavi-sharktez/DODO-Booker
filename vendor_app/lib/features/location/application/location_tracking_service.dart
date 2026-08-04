import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/supabase_client_provider.dart';
import '../data/location_repository.dart';
import '../../auth/presentation/providers/auth_controller.dart';
import '../../bookings/domain/models/booking.dart';
import '../../bookings/presentation/providers/bookings_provider.dart';

final locationRepositoryProvider = Provider<LocationRepository>((ref) {
  return LocationRepository(ref.watch(supabaseClientProvider));
});

final locationTrackingServiceProvider = Provider<LocationTrackingService>((ref) {
  final repository = ref.watch(locationRepositoryProvider);
  final service = LocationTrackingService(repository);
  ref.onDispose(() => service.dispose());
  return service;
});

final activeBookingTrackerObserver = Provider.autoDispose<void>((ref) {
  final user = ref.watch(currentVendorUserProvider);
  final asyncBookings = ref.watch(vendorBookingsProvider);
  
  debugPrint('[GPS][Trace][1] activeBookingTrackerObserver triggered — user=${user?.id}, bookingsState=${asyncBookings.runtimeType}');

  if (user == null) return;

  asyncBookings.whenData((bookings) {
    debugPrint('[GPS][Trace][1b] Bookings loaded: count=${bookings.length}, statuses=${bookings.map((b) => "${b.id.substring(0, 6)}:${b.status}").toList()}');

    Booking? activeBooking;
    for (final b in bookings) {
      final s = b.status.toLowerCase().trim();
      if (s == 'in_progress' ||
          s == 'awaiting_verification' ||
          s == 'accepted' ||
          s == 'assigned') {
        activeBooking = b;
        break;
      }
    }

    final trackingService = ref.read(locationTrackingServiceProvider);

    if (activeBooking != null) {
      debugPrint('[GPS][Trace][1c] Found active booking ${activeBooking.id} with status ${activeBooking.status}');
      trackingService.syncBookingTracking(
        bookingId: activeBooking.id,
        vendorId: user.id,
        bookingStatus: activeBooking.status,
      );
    } else {
      debugPrint('[GPS][Trace][1c] No active booking found — stopping tracking.');
      trackingService.stopTracking();
    }
  });
});

class LocationTrackingService {
  LocationTrackingService(this._repository);

  final LocationRepository _repository;

  Timer? _timer;
  String? _activeBookingId;
  String? _activeVendorId;
  Position? _lastLoggedPosition;
  bool _isChecking = false;

  /// Min movement in meters required before logging a new point
  static const double minDistanceMeters = 20.0;

  /// Min accuracy change in meters required before logging
  static const double minAccuracyDeltaMeters = 15.0;

  /// Interval between location checks (approx 45 seconds)
  static const Duration checkInterval = Duration(seconds: 45);

  bool get isTracking => _timer != null && _timer!.isActive;
  String? get activeBookingId => _activeBookingId;

  /// Starts or updates active booking location tracking.
  /// If booking status is terminal ('completed', 'cancelled', 'rejected'), stops tracking.
  Future<void> syncBookingTracking({
    required String bookingId,
    required String vendorId,
    required String bookingStatus,
  }) async {
    debugPrint('[GPS][Trace][2] syncBookingTracking called — bookingId=$bookingId, vendorId=$vendorId, status=$bookingStatus');

    final terminalStatuses = {'completed', 'cancelled', 'rejected'};
    if (terminalStatuses.contains(bookingStatus.toLowerCase().trim())) {
      debugPrint('[GPS][Trace][2a] Booking $bookingId status is terminal ($bookingStatus) — stopping tracking.');
      stopTracking();
      return;
    }

    final activeStatuses = {'assigned', 'accepted', 'in_progress', 'awaiting_verification'};
    if (!activeStatuses.contains(bookingStatus.toLowerCase().trim())) {
      debugPrint('[GPS][Trace][2b] Booking $bookingId status ($bookingStatus) is not active — stopping tracking.');
      stopTracking();
      return;
    }

    if (_activeBookingId == bookingId && isTracking) {
      debugPrint('[GPS][Trace][2c] Tracking already active for booking $bookingId');
      return;
    }

    _activeBookingId = bookingId;
    _activeVendorId = vendorId;
    _lastLoggedPosition = null;

    debugPrint('[GPS][Trace][3] Starting periodic tracking timer for booking $bookingId (vendor: $vendorId)');

    _timer?.cancel();
    // Immediate first check
    _captureAndLogLocation();

    // Periodic interval checks
    _timer = Timer.periodic(checkInterval, (_) => _captureAndLogLocation());
  }

  /// Stops tracking timer and resets state.
  void stopTracking() {
    if (_timer != null) {
      debugPrint('[GPS][Trace][3-stop] Stopping location tracking timer for booking $_activeBookingId');
      _timer?.cancel();
      _timer = null;
    }
    _activeBookingId = null;
    _activeVendorId = null;
    _lastLoggedPosition = null;
    _isChecking = false;
  }

  Future<void> _captureAndLogLocation() async {
    debugPrint('[GPS][Trace][4] _captureAndLogLocation invoked — isChecking=$_isChecking, activeBookingId=$_activeBookingId, activeVendorId=$_activeVendorId');

    if (_isChecking || _activeBookingId == null || _activeVendorId == null) return;
    _isChecking = true;

    try {
      // 1. Permission check & request with timeouts to prevent hanging
      bool serviceEnabled = true;
      try {
        serviceEnabled = await Geolocator.isLocationServiceEnabled()
            .timeout(const Duration(seconds: 3), onTimeout: () => true);
      } catch (e) {
        debugPrint('[GPS][Trace][4a-warning] isLocationServiceEnabled check failed or unsupported: $e');
      }
      debugPrint('[GPS][Trace][4a] Location service enabled: $serviceEnabled');

      LocationPermission permission = LocationPermission.whileInUse;
      try {
        permission = await Geolocator.checkPermission()
            .timeout(const Duration(seconds: 3), onTimeout: () => LocationPermission.whileInUse);
      } catch (e) {
        debugPrint('[GPS][Trace][4b-warning] checkPermission check failed: $e');
      }
      debugPrint('[GPS][Trace][4b] Check permission result: $permission');

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission()
            .timeout(const Duration(seconds: 5), onTimeout: () => LocationPermission.denied);
        debugPrint('[GPS][Trace][4b-request] Request permission result: $permission');
        if (permission == LocationPermission.denied) {
          debugPrint('[GPS][Trace][4b-error] Location permission denied by user.');
          _isChecking = false;
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        debugPrint('[GPS][Trace][4b-error] Location permission permanently denied.');
        _isChecking = false;
        return;
      }

      // 2. Capture current position with fallback
      debugPrint('[GPS][Trace][4c] Fetching current position from Geolocator…');
      Position? currentPos;
      try {
        currentPos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 8),
          ),
        );
      } catch (e) {
        debugPrint('[GPS][Trace][4c-fallback] getCurrentPosition failed ($e) — trying getLastKnownPosition…');
        try {
          currentPos = await Geolocator.getLastKnownPosition();
        } catch (_) {}
      }

      if (currentPos == null) {
        debugPrint('[GPS][Trace][4c-error] Unable to acquire location fix (currentPos is null).');
        _isChecking = false;
        return;
      }

      debugPrint('[GPS][Trace][4d] Position captured: lat=${currentPos.latitude}, lng=${currentPos.longitude}, accuracy=${currentPos.accuracy}m');

      // 3. HARD ACCURACY DISCARD: Discard locations with accuracy > 100 meters immediately
      if (currentPos.accuracy > maxAccuracyThresholdMeters) {
        debugPrint(
          '[GPS][Trace][4d-DISCARD] Position discarded — accuracy (${currentPos.accuracy.toStringAsFixed(1)}m) '
          'exceeds max threshold (${maxAccuracyThresholdMeters}m). Skipping insert.',
        );
        _isChecking = false;
        return;
      }

      // 4. Distance & accuracy delta filter
      final shouldLog = _shouldLogPosition(currentPos);
      debugPrint('[GPS][Trace][4e] Filter check result (_shouldLogPosition): $shouldLog (isFirstLog=${_lastLoggedPosition == null})');

      if (!shouldLog) {
        debugPrint('[GPS][Trace][4e-skip] Position skipped — distance/accuracy delta insufficient.');
        _isChecking = false;
        return;
      }

      // 4. Log location to backend
      debugPrint('[GPS][Trace][5] Invoking logLocation RPC for booking $_activeBookingId…');
      final logId = await _repository.logLocation(
        bookingId: _activeBookingId!,
        vendorId: _activeVendorId!,
        latitude: currentPos.latitude,
        longitude: currentPos.longitude,
        accuracy: currentPos.accuracy,
      );

      debugPrint('[GPS][Trace][6] RPC execution complete — return logId: $logId');

      if (logId != null) {
        _lastLoggedPosition = currentPos;
        debugPrint('[GPS][Trace][7] Successfully logged vendor location to DB! Row ID: $logId');
      } else {
        debugPrint('[GPS][Trace][7-error] logLocation returned null (RPC failed or error caught)');
      }
    } catch (e, stack) {
      debugPrint('[GPS][Trace][ERROR] Exception during _captureAndLogLocation: $e\n$stack');
    } finally {
      _isChecking = false;
    }
  }

  /// Max acceptable GPS accuracy threshold in meters
  static const double maxAccuracyThresholdMeters = 100.0;

  bool _shouldLogPosition(Position newPos) {
    // Ignore positions with poor accuracy (> 100 meters)
    if (newPos.accuracy > maxAccuracyThresholdMeters) {
      debugPrint(
        '[GPS][Trace][Filter] Position skipped — accuracy (${newPos.accuracy.toStringAsFixed(1)}m) '
        'exceeds maximum threshold (${maxAccuracyThresholdMeters}m)',
      );
      return false;
    }

    if (_lastLoggedPosition == null) return true;

    final distance = Geolocator.distanceBetween(
      _lastLoggedPosition!.latitude,
      _lastLoggedPosition!.longitude,
      newPos.latitude,
      newPos.longitude,
    );

    final accuracyDelta = (newPos.accuracy - _lastLoggedPosition!.accuracy).abs();
    debugPrint('[GPS][Trace][Filter] Calculated distance=${distance.toStringAsFixed(1)}m (min: $minDistanceMeters m), accuracyDelta=${accuracyDelta.toStringAsFixed(1)}m');

    return distance >= minDistanceMeters || accuracyDelta >= minAccuracyDeltaMeters;
  }

  void dispose() {
    stopTracking();
  }
}
