import 'package:flutter/foundation.dart';
import '../../../shared/repositories/base_repository.dart';
import '../domain/models/vendor_location_log.dart';

class LocationRepository extends BaseRepository {
  const LocationRepository(super.supabase);

  /// Logs vendor location coordinates via `log_vendor_location` RPC.
  Future<String?> logLocation({
    required String bookingId,
    required String vendorId,
    required double latitude,
    required double longitude,
    double? accuracy,
  }) async {
    try {
      final res = await supabase.rpc('log_vendor_location', params: {
        'p_booking_id': bookingId,
        'p_vendor_id': vendorId,
        'p_latitude': latitude,
        'p_longitude': longitude,
        'p_accuracy': accuracy,
      });

      debugPrint('[GPS][Repo] log_vendor_location RPC returned: $res');
      return res as String?;
    } catch (e) {
      debugPrint('[GPS][Repo][ERROR] log_vendor_location RPC failed: $e');
      return null;
    }
  }

  /// Fetches latest location logs for a booking.
  Future<List<VendorLocationLog>> fetchLocationLogs(String bookingId) async {
    try {
      final res = await supabase
          .from('vendor_location_logs')
          .select()
          .eq('booking_id', bookingId)
          .order('recorded_at', ascending: false);

      final list = res as List<dynamic>;
      return list
          .map((json) => VendorLocationLog.fromMap(json as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }
}
