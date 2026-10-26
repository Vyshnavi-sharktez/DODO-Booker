import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/services/fcm_service.dart';

class AuthService {
  static const _phoneKey = 'dodo_auth_phone';
  static const _customerIdKey = 'dodo_customer_id';
  final SupabaseClient _client = Supabase.instance.client;

  // ── Phone check ────────────────────────────────────────────────────────────

  /// Sends an OTP to [phone] via Supabase Auth phone OTP (MSG91).
  /// Accepts any valid mobile number — registered or new.
  Future<void> checkPhone(String phone) async {
    await _client.auth.signInWithOtp(phone: phone, shouldCreateUser: true);
  }

  // ── OTP verification ───────────────────────────────────────────────────────

  /// Verifies [otp] for [phone] via Supabase Auth.
  /// On success: creates or links the customer record via the
  /// ensure_customer_linked RPC and persists the session in SharedPreferences.
  Future<void> verifyOtp(String phone, String otp) async {
    await _client.auth.verifyOTP(
      phone: phone,
      token: otp,
      type: OtpType.sms,
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_phoneKey, phone);
    debugPrint('[DODO][Auth] Login Success');

    try {
      final customerId = await _client.rpc(
        'ensure_customer_linked',
        params: {'p_phone': phone},
      ) as String;
      await prefs.setString(_customerIdKey, customerId);
      await CustomerFcmService.initialize(customerId, phone);
    } catch (e) {
      debugPrint('[DODO][Customer] Warning: could not sync customer record: $e');
    }
  }

  // ── Session ────────────────────────────────────────────────────────────────

  /// Returns true if a session phone is stored locally.
  Future<bool> isAuthenticated() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_phoneKey) != null;
  }

  /// Returns the locally stored phone, or null if not signed in.
  Future<String?> currentPhone() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_phoneKey);
  }

  // ── Profile ────────────────────────────────────────────────────────────────

  /// Reads profile_complete from the customers table for the current session.
  Future<bool> isProfileComplete() async {
    final phone = await currentPhone();
    if (phone == null) return false;
    final row = await _client
        .from('customers')
        .select('profile_complete')
        .eq('phone', phone)
        .maybeSingle();
    return row?['profile_complete'] as bool? ?? false;
  }

  /// Updates full_name + email in customers; sets profile_complete = true.
  Future<void> updateProfile({
    required String fullName,
    required String email,
  }) async {
    debugPrint('[DODO][Profile] updateProfile called');

    final phone = await currentPhone();
    debugPrint('[DODO][Profile] Current phone: $phone');
    debugPrint('[DODO][Profile] Name: $fullName, Email: $email');

    if (phone == null) {
      throw Exception('Not authenticated.');
    }

    final updated = await _client
        .from('customers')
        .update({
          'full_name': fullName,
          'email': email,
          'profile_complete': true,
        })
        .eq('phone', phone)
        .select();

    debugPrint('[DODO][Profile] Supabase update raw response: $updated');

    if ((updated as List).isEmpty) {
      // Customer row missing — create it now as a fallback.
      debugPrint('[DODO][Profile] No customer row found — creating');
      await _client.from('customers').insert({
        'phone': phone,
        'full_name': fullName,
        'email': email,
        'is_active': true,
        'profile_complete': true,
      });
    } else {
      final id = updated.first['id'];
      debugPrint('[DODO][Profile] Customer updated: id=$id');
    }
    debugPrint('[DODO][Auth] Profile Completed');
  }

  // ── Session restore ────────────────────────────────────────────────────────

  /// Called on app startup to re-register the FCM token for an existing session.
  Future<void> initFcmIfSessionExists() async {
    final prefs = await SharedPreferences.getInstance();
    final phone = prefs.getString(_phoneKey);
    final customerId = prefs.getString(_customerIdKey);
    if (phone == null || customerId == null) return;
    try {
      await CustomerFcmService.initialize(customerId, phone);
    } catch (_) {}
  }

  // ── Sign out ───────────────────────────────────────────────────────────────

  /// Clears the local session and the Supabase Auth session.
  Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    final phone = prefs.getString(_phoneKey);
    final customerId = prefs.getString(_customerIdKey);
    if (phone != null && customerId != null) {
      try {
        await CustomerFcmService.clearToken(customerId, phone);
      } catch (_) {}
    }
    await prefs.remove(_phoneKey);
    await prefs.remove(_customerIdKey);
    try {
      await _client.auth.signOut();
    } catch (_) {}
  }
}
