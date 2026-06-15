import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthRemoteDatasource {
  const AuthRemoteDatasource(this._client);
  final SupabaseClient _client;

  static const _phoneKey = 'dodo_vendor_phone';

  // ── Phone check ──────────────────────────────────────────────────────────────
  // Validates that the phone is registered in vendor_dev_auth.
  // OTP is pre-seeded in the table — no SMS is sent.

  Future<void> checkPhone(String phone) async {
    debugPrint('[DODO][Datasource] checkPhone called');
    debugPrint('[DODO][Datasource] table      : vendor_dev_auth');
    debugPrint('[DODO][Datasource] column     : phone');
    debugPrint('[DODO][Datasource] value      : "$phone"');
    debugPrint('[DODO][Datasource] length     : ${phone.length}');
    debugPrint('[DODO][Datasource] codeUnits  : ${phone.codeUnits}');

    final row = await _client
        .from('vendor_dev_auth')
        .select('phone')
        .eq('phone', phone)
        .maybeSingle();

    debugPrint('[DODO][Datasource] raw response: $row');

    if (row == null) {
      debugPrint('[DODO][Datasource] row is null — no match found');
      throw Exception('This number is not registered as a vendor.');
    }
    debugPrint('[DODO][Datasource] match found: $row');
  }

  // ── OTP verification ─────────────────────────────────────────────────────────
  // Matches phone + otp against vendor_dev_auth row.

  Future<void> verifyOtp({
    required String phone,
    required String otp,
  }) async {
    final row = await _client
        .from('vendor_dev_auth')
        .select('phone')
        .eq('phone', phone)
        .eq('otp', otp)
        .maybeSingle();
    if (row == null) throw Exception('Invalid OTP. Please try again.');
  }

  // ── Vendor profile ───────────────────────────────────────────────────────────
  // Fetches the vendor row from the vendors table by phone.

  Future<Map<String, dynamic>?> getVendorByPhone(String phone) async {
    debugPrint('[AUTH] getVendorByPhone — value   : "$phone"');
    debugPrint('[AUTH] getVendorByPhone — length  : ${phone.length}');
    debugPrint('[AUTH] getVendorByPhone — codeUnits: ${phone.codeUnits}');
    try {
      final rows = await _client
          .from('vendors')
          .select()
          .eq('phone', phone)
          .limit(1);
      debugPrint('[AUTH] getVendorByPhone — rowCount : ${rows.length}');
      if (rows.isEmpty) {
        debugPrint('[AUTH] getVendorByPhone — result  : NULL (no match)');
        return null;
      }
      debugPrint('[AUTH] getVendorByPhone — result  : FOUND id=${rows.first['id']}');
      return rows.first;
    } catch (e) {
      debugPrint('[AUTH] getVendorByPhone — EXCEPTION: $e');
      rethrow;
    }
  }

  // ── Session ──────────────────────────────────────────────────────────────────
  // Session = phone number stored in SharedPreferences (mirrors Customer App).

  Future<String?> getSavedPhone() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_phoneKey);
  }

  Future<void> savePhone(String phone) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_phoneKey, phone);
  }

  Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_phoneKey);
  }
}
