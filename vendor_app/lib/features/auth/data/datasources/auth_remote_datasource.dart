import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthRemoteDatasource {
  const AuthRemoteDatasource(this._client);
  final SupabaseClient _client;

  static const _phoneKey = 'dodo_vendor_phone';

  // ── Phone check + OTP send ───────────────────────────────────────────────

  /// Verifies the phone is registered as a vendor/team member via RPC,
  /// then sends a real SMS OTP via Supabase Phone Auth (Twilio).
  Future<void> checkPhone(String phone) async {
    final registered = await _client.rpc(
          'check_vendor_phone',
          params: {'p_phone': phone},
        ) as bool? ??
        false;
    if (!registered) {
      throw Exception('This number is not registered as a vendor.');
    }
    await _client.auth.signInWithOtp(phone: phone);
  }

  // ── OTP verification ─────────────────────────────────────────────────────

  Future<void> verifyOtp({
    required String phone,
    required String otp,
  }) async {
    await _client.auth.verifyOTP(
      phone: phone,
      token: otp,
      type: OtpType.sms,
    );
  }

  // ── Vendor/team profile ──────────────────────────────────────────────────

  Future<Map<String, dynamic>?> getVendorByPhone(String phone) async {
    final rows =
        await _client.from('vendors').select().eq('phone', phone).limit(1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<Map<String, dynamic>?> getDodoTeamByPhone(String phone) async {
    final rows =
        await _client.from('dodo_teams').select().eq('phone', phone).limit(1);
    return rows.isEmpty ? null : rows.first;
  }

  // ── Auth user linking ────────────────────────────────────────────────────

  /// Calls ensure_vendor_linked RPC to write auth_user_id into the vendors row.
  /// No-ops for dodo_team members (they have no vendors row).
  Future<void> linkVendor(String phone) async {
    try {
      await _client
          .rpc('ensure_vendor_linked', params: {'p_phone': phone});
    } catch (_) {}
  }

  // ── Session ──────────────────────────────────────────────────────────────

  /// Returns phone from the active Supabase session, or SharedPreferences fallback.
  Future<String?> getSavedPhone() async {
    final phone = _client.auth.currentUser?.phone;
    if (phone != null && phone.isNotEmpty) return phone;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_phoneKey);
  }

  Future<void> savePhone(String phone) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_phoneKey, phone);
  }

  /// Signs out from Supabase and removes the cached phone from SharedPreferences.
  Future<void> clearSession() async {
    try {
      await _client.auth.signOut();
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_phoneKey);
  }
}
