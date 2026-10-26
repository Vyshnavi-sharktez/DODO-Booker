import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthRemoteDatasource {
  const AuthRemoteDatasource(this._client);
  final SupabaseClient _client;

  static const _phoneKey = 'dodo_vendor_phone';

  // ── Phone check ──────────────────────────────────────────────────────────────
  // Sends an OTP to any valid mobile number via Supabase Auth phone OTP (MSG91).

  Future<void> checkPhone(String phone) async {
    await _client.auth.signInWithOtp(phone: phone, shouldCreateUser: true);
  }

  // ── OTP verification ─────────────────────────────────────────────────────────
  // Verifies the OTP via Supabase Auth. Throws AuthException on failure.

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

  // ── Vendor record management ─────────────────────────────────────────────────

  /// Links the current auth user to an existing vendor row, or creates a new
  /// minimal vendor record if no row exists for [phone].
  /// Returns the vendor UUID (existing or newly created).
  /// Throws if the caller is not authenticated.
  Future<String> ensureVendorCreated(String phone) async {
    final result = await _client.rpc(
      'ensure_vendor_created',
      params: {'p_phone': phone},
    );
    return result as String;
  }

  // ── Vendor profile ───────────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> getVendorByPhone(String phone) async {
    final rows = await _client
        .from('vendors')
        .select()
        .eq('phone', phone)
        .limit(1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<Map<String, dynamic>?> getDodoTeamByPhone(String phone) async {
    final rows = await _client
        .from('dodo_teams')
        .select()
        .eq('phone', phone)
        .limit(1);
    return rows.isEmpty ? null : rows.first;
  }

  // ── Session ──────────────────────────────────────────────────────────────────

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
    try {
      await _client.auth.signOut();
    } catch (_) {}
  }
}
