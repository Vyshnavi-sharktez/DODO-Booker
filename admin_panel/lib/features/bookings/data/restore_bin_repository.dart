import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/models/booking.dart';
import '../domain/models/deleted_booking.dart';

class RestoreBinRepository {
  final SupabaseClient _supabase;

  const RestoreBinRepository(this._supabase);

  // ── Fetch all deleted bookings (joined with customer + admin names) ─────────

  Future<List<DeletedBooking>> fetchDeletedBookings() async {
    final data = await _supabase.rpc('admin_fetch_deleted_bookings');
    return (data as List<dynamic>)
        .map((r) => DeletedBooking.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  // ── Restore a single booking ────────────────────────────────────────────────

  Future<Map<String, dynamic>> restoreBooking(String bookingId) async {
    final result = await _supabase.rpc(
      'admin_restore_booking',
      params: {'p_booking_id': bookingId},
    );
    return result as Map<String, dynamic>;
  }

  // ── Purge expired bookings ─────────────────────────────────────────────────

  Future<Map<String, dynamic>> purgeExpiredBookings() async {
    final result = await _supabase.rpc('admin_purge_expired_bookings');
    return result as Map<String, dynamic>;
  }

  // ── Retention settings (stored in the shared settings table) ──────────────

  Future<({int value, String unit})> fetchRetentionSettings() async {
    final rows = await _supabase
        .from('settings')
        .select('setting_key, setting_value')
        .inFilter('setting_key', [
          'deleted_bookings_retention_value',
          'deleted_bookings_retention_unit',
        ]);

    int value = 30;
    String unit = 'days';

    for (final row in rows as List<dynamic>) {
      final m = row as Map<String, dynamic>;
      final key = m['setting_key'] as String;
      final val = m['setting_value'] as String? ?? '';
      if (key == 'deleted_bookings_retention_value') {
        value = int.tryParse(val) ?? 30;
      } else if (key == 'deleted_bookings_retention_unit') {
        if (['days', 'weeks', 'months'].contains(val)) unit = val;
      }
    }

    return (value: value, unit: unit);
  }

  // ── Fetch full detail for a single archived booking ─────────────────────────

  Future<Booking> fetchDeletedBookingDetail(String bookingId) async {
    final data = await _supabase.rpc(
      'admin_fetch_deleted_booking_detail',
      params: {'p_booking_id': bookingId},
    );
    return Booking.fromMap(data as Map<String, dynamic>);
  }

  Future<void> saveRetentionSettings(int value, String unit) async {
    await _supabase.from('settings').upsert([
      {'setting_key': 'deleted_bookings_retention_value', 'setting_value': value.toString()},
      {'setting_key': 'deleted_bookings_retention_unit',  'setting_value': unit},
    ], onConflict: 'setting_key');
  }
}
