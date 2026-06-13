import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/models/rejected_booking_record.dart';

class RejectedBookingsLocalDatasource {
  static const _keyPrefix = 'dodo_rejected_bookings_';

  Future<List<RejectedBookingRecord>> load(String vendorId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_keyPrefix$vendorId');
    if (raw == null) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => RejectedBookingRecord.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> add(String vendorId, RejectedBookingRecord record) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_keyPrefix$vendorId';
    final raw = prefs.getString(key);
    final existing = raw != null
        ? (jsonDecode(raw) as List<dynamic>)
            .map((e) =>
                RejectedBookingRecord.fromJson(e as Map<String, dynamic>))
            .toList()
        : <RejectedBookingRecord>[];
    final updated = [
      record,
      ...existing.where((r) => r.id != record.id),
    ];
    await prefs.setString(
      key,
      jsonEncode(updated.map((r) => r.toJson()).toList()),
    );
  }
}
