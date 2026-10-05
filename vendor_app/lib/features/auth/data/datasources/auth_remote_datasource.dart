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
    final row = await _client
        .from('vendor_dev_auth')
        .select('phone')
        .eq('phone', phone)
        .maybeSingle();

    if (row == null) throw Exception('This number is not registered as a vendor.');
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
    final rows = await _client
        .from('vendors')
        .select()
        .eq('phone', phone)
        .limit(1);
    return rows.isEmpty ? null : rows.first;
  }

  /// Checks if the phone belongs to a DODO Team (supervisor phone).
  Future<Map<String, dynamic>?> getDodoTeamByPhone(String phone) async {
    final rows = await _client
        .from('dodo_teams')
        .select()
        .eq('phone', phone)
        .limit(1);
    return rows.isEmpty ? null : rows.first;
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
