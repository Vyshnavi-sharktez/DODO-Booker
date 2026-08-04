import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/models/gps_cancellation_audit.dart';

class GpsAuditRepository {
  final SupabaseClient _supabase;

  const GpsAuditRepository(this._supabase);

  Future<List<GpsCancellationAudit>> fetchGpsCancellationAudits() async {
    final data = await _supabase
        .from('gps_cancellation_audits')
        .select('''
          *,
          bookings:booking_id (booking_number),
          customers:customer_id (full_name, phone),
          vendors:vendor_id (business_name, phone)
        ''')
        .order('audited_at', ascending: false);

    return (data as List<dynamic>)
        .map((r) => GpsCancellationAudit.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<void> updateAuditStatus({
    required String auditId,
    required String newStatus,
  }) async {
    await _supabase
        .from('gps_cancellation_audits')
        .update({'audit_status': newStatus})
        .eq('id', auditId);
  }
}
