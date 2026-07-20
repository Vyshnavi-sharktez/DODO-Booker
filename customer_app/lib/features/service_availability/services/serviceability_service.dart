import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum ServiceabilityResult {
  /// Address is within an active service zone (or no zones configured).
  serviceable,

  /// Active zones exist and the address coordinates fall outside all of them.
  notServiceable,

  /// Active zones are configured but the address has no coordinates — we
  /// cannot determine serviceability without a location.
  noCoordinates,

  /// The RPC call failed (network error, backend issue). We know neither
  /// whether the area is served nor whether the coordinates are valid.
  error,
}

/// Checks whether a booking address is within DODO Booker's configured
/// Service Availability Areas.
///
/// Call [check] with the address lat/lng (nullable).
///
/// Behavior by case:
///   • No active zones configured           → serviceable (opt-in feature)
///   • Has coordinates + inside a zone      → serviceable
///   • Has coordinates + outside all zones  → notServiceable
///   • No coordinates + active zones exist  → noCoordinates (block)
///   • No coordinates + no active zones     → serviceable (zones irrelevant)
///   • RPC / network error                  → error (block, show retry message)
///   • hasActiveAreas check itself fails    → error (any DB failure where
///       serviceability cannot be reliably determined must not silently pass)
class ServiceabilityService {
  final _client = Supabase.instance.client;

  Future<ServiceabilityResult> check(double? lat, double? lng) async {
    if (lat == null || lng == null) {
      return _handleMissingCoordinates();
    }

    try {
      debugPrint('[DODO][Serviceability] checking lat=$lat lng=$lng');
      final result = await _client.rpc(
        'is_location_serviceable',
        params: {'p_lat': lat, 'p_lng': lng},
      );
      final serviceable = result as bool? ?? true;
      debugPrint('[DODO][Serviceability] result=$serviceable');
      return serviceable
          ? ServiceabilityResult.serviceable
          : ServiceabilityResult.notServiceable;
    } catch (e) {
      debugPrint('[DODO][Serviceability] RPC error: $e');
      return ServiceabilityResult.error;
    }
  }

  /// Called when the address has no coordinates.
  /// Only blocks if at least one active zone is configured — if no zones
  /// exist the check is irrelevant and the customer should not be blocked.
  Future<ServiceabilityResult> _handleMissingCoordinates() async {
    debugPrint('[DODO][Serviceability] address has no coordinates');
    try {
      final rows = await _client
          .from('service_availability_areas')
          .select('id')
          .eq('is_active', true)
          .limit(1);
      final hasActiveZones = (rows as List).isNotEmpty;
      debugPrint(
          '[DODO][Serviceability] hasActiveZones=$hasActiveZones (no coords)');
      return hasActiveZones
          ? ServiceabilityResult.noCoordinates
          : ServiceabilityResult.serviceable;
    } catch (e) {
      debugPrint(
          '[DODO][Serviceability] zone-check error: $e — returning error');
      return ServiceabilityResult.error;
    }
  }
}
