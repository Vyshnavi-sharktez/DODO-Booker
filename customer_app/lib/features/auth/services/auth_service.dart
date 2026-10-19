import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/services/fcm_service.dart';

class AuthService {
  static const _phoneKey = 'dodo_auth_phone';
  static const _customerIdKey = 'dodo_customer_id';
  final SupabaseClient _client = Supabase.instance.client;

  // ── OTP ────────────────────────────────────────────────────────────────────

  /// Sends a real SMS OTP to [phone] via Supabase Phone Auth (Twilio).
  Future<void> sendOtp(String phone) async {
    await _client.auth.signInWithOtp(phone: phone);
    debugPrint('[DODO][Auth] OTP sent to $phone');
  }

  /// Verifies [otp] via Supabase, links the auth user to a customer record,
  /// persists session keys, and registers the FCM token.
  Future<void> verifyOtp(String phone, String otp) async {
    await _client.auth.verifyOTP(
      phone: phone,
      token: otp,
      type: OtpType.sms,
    );
    debugPrint('[DODO][Auth] OTP verified for $phone');

    final customerId = await _ensureCustomerLinked(phone);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_phoneKey, phone);
    await prefs.setString(_customerIdKey, customerId);
    debugPrint('[DODO][Auth] Login Success customer=$customerId');

    try {
      await CustomerFcmService.initialize(customerId, phone);
    } catch (e) {
      debugPrint('[DODO][Customer] Warning: FCM register failed: $e');
    }
  }

  // ── Customer record ────────────────────────────────────────────────────────

  /// Calls the ensure_customer_linked RPC which links the current auth user to
  /// their customer row (or creates one) and returns the customer UUID.
  Future<String> _ensureCustomerLinked(String phone) async {
    final result = await _client.rpc(
      'ensure_customer_linked',
      params: {'p_phone': phone},
    );
    if (result == null) throw Exception('Could not link customer account');
    return result as String;
  }

  // ── Session ────────────────────────────────────────────────────────────────

  /// Returns true if there is a valid Supabase session or a persisted phone key.
  Future<bool> isAuthenticated() async {
    if (_client.auth.currentSession != null) return true;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_phoneKey) != null;
  }

  /// Returns the current phone from the Supabase session or SharedPreferences.
  Future<String?> currentPhone() async {
    final phone = _client.auth.currentUser?.phone;
    if (phone != null && phone.isNotEmpty) return phone;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_phoneKey);
  }

  // ── Profile ────────────────────────────────────────────────────────────────

  /// Reads profile_complete from customers; falls back to dev_auth for legacy users.
  Future<bool> isProfileComplete() async {
    final phone = await currentPhone();
    if (phone == null) return false;
    final row = await _client
        .from('customers')
        .select('profile_complete')
        .eq('phone', phone)
        .maybeSingle();
    if (row != null) return row['profile_complete'] as bool? ?? false;
    // Legacy: user exists only in dev_auth (pre-migration session)
    final legacy = await _client
        .from('dev_auth')
        .select('profile_complete')
        .eq('phone', phone)
        .maybeSingle();
    return legacy?['profile_complete'] as bool? ?? false;
  }

  /// Updates full_name + email in customers and sets profile_complete = true.
  /// Also writes to dev_auth for users that still have a legacy row there.
  Future<void> updateProfile({
    required String fullName,
    required String email,
  }) async {
    debugPrint('[DODO][Profile] updateProfile called');
    final phone = await currentPhone();
    if (phone == null) throw Exception('Not authenticated.');

    final updated = await _client
        .from('customers')
        .update({
          'full_name': fullName,
          'email': email,
          'profile_complete': true,
        })
        .eq('phone', phone)
        .select('id');

    if ((updated as List).isEmpty) {
      throw Exception(
          'Profile update failed: customer row not found for phone $phone');
    }
    debugPrint('[DODO][Auth] Profile Completed');

    // Best-effort: keep dev_auth in sync for existing legacy rows
    try {
      await _client.from('dev_auth').update({
        'full_name': fullName,
        'email': email,
        'profile_complete': true,
      }).eq('phone', phone);
    } catch (_) {}
  }

  // ── Session restore ────────────────────────────────────────────────────────

  /// Re-registers the FCM token for an existing session on app startup.
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

  /// Signs out from Supabase, clears FCM token, and removes SharedPreferences keys.
  Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    final phone = prefs.getString(_phoneKey);
    final customerId = prefs.getString(_customerIdKey);
    if (phone != null && customerId != null) {
      try {
        await CustomerFcmService.clearToken(customerId, phone);
      } catch (_) {}
    }
    try {
      await _client.auth.signOut();
    } catch (_) {}
    await prefs.remove(_phoneKey);
    await prefs.remove(_customerIdKey);
  }
}
