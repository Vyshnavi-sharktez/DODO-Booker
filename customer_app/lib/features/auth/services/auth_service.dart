import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/services/fcm_service.dart';

class AuthService {
  static const _phoneKey = 'dodo_auth_phone';
  static const _customerIdKey = 'dodo_customer_id';
  final SupabaseClient _client = Supabase.instance.client;

  // ── Phone check ────────────────────────────────────────────────────────────

  /// Checks that [phone] exists in dev_auth. Throws if not registered.
  Future<void> checkPhone(String phone) async {
    final row = await _client
        .from('dev_auth')
        .select('phone')
        .eq('phone', phone)
        .maybeSingle();

    if (row == null) {
      throw Exception('This number is not registered.');
    }
  }

  // ── OTP verification ───────────────────────────────────────────────────────

  /// Validates [otp] against dev_auth for [phone]. Persists session on success.
  /// Also ensures a customer record exists in the customers table.
  Future<void> verifyOtp(String phone, String otp) async {
    final row = await _client
        .from('dev_auth')
        .select('phone')
        .eq('phone', phone)
        .eq('otp', otp)
        .maybeSingle();

    if (row == null) {
      throw Exception('Invalid OTP. Please try again.');
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_phoneKey, phone);
    debugPrint('[DODO][Auth] Login Success');

    // Ensure customer record exists, then register FCM token.
    try {
      final customerId = await _ensureCustomerExists(phone);
      await prefs.setString(_customerIdKey, customerId);
      await CustomerFcmService.initialize(customerId, phone);
    } catch (e) {
      debugPrint('[DODO][Customer] Warning: could not sync customer record after login');
    }
  }

  // ── Customer record ────────────────────────────────────────────────────────

  /// Checks if a customer exists for [phone]; inserts a placeholder row if not.
  /// Returns the customer UUID in both cases.
  Future<String> _ensureCustomerExists(String phone) async {
    final existing = await _client
        .from('customers')
        .select('id')
        .eq('phone', phone)
        .maybeSingle();

    if (existing != null) {
      debugPrint('[DODO][Customer] Customer found: id=${existing['id']}');
      return existing['id'] as String;
    }

    debugPrint('[DODO][Customer] Creating customer');
    final created = await _client
        .from('customers')
        .insert({
          'phone': phone,
          'full_name': '',
          'email': '',
          'is_active': true,
        })
        .select('id')
        .single();
    debugPrint('[DODO][Customer] Customer created successfully: id=${created['id']}');
    return created['id'] as String;
  }

  /// Updates the customers row for [phone] with name + email.
  /// Falls back to insert if the row doesn't exist yet (edge case).
  Future<void> _syncCustomerProfile({
    required String phone,
    required String fullName,
    required String email,
  }) async {
    final updated = await _client
        .from('customers')
        .update({'full_name': fullName, 'email': email})
        .eq('phone', phone)
        .select('id');

    final updatedList = updated as List;

    if (updatedList.isEmpty) {
      // Customer row is missing — create it now as a fallback.
      debugPrint('[DODO][Customer] Customer not found during profile sync — creating');
      final created = await _client
          .from('customers')
          .insert({
            'phone': phone,
            'full_name': fullName,
            'email': email,
            'is_active': true,
          })
          .select('id, phone')
          .single();
      debugPrint('[DODO][Customer] Customer created successfully: id=${created['id']}');
    } else {
      final id = (updatedList.first as Map<String, dynamic>)['id'];
      debugPrint('[DODO][Customer] Customer updated successfully: id=$id');
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

  /// Reads profile_complete from dev_auth for the current session phone.
  Future<bool> isProfileComplete() async {
    final phone = await currentPhone();
    if (phone == null) return false;
    final row = await _client
        .from('dev_auth')
        .select('profile_complete')
        .eq('phone', phone)
        .single();
    return row['profile_complete'] as bool? ?? false;
  }

  /// Updates full_name + email in dev_auth AND customers; sets profile_complete = true.
  Future<void> updateProfile({
    required String fullName,
    required String email,
  }) async {
    debugPrint('[DODO][Profile] updateProfile called');

    final phone = await currentPhone();
    debugPrint('[DODO][Profile] Current phone: $phone');
    debugPrint('[DODO][Profile] Name: $fullName');
    debugPrint('[DODO][Profile] Email: $email');

    if (phone == null) {
      debugPrint('[DODO][Profile] Supabase update failed: no session phone in SharedPreferences');
      throw Exception('Not authenticated.');
    }

    try {
      // ── 1. Update dev_auth ─────────────────────────────────────────────────
      final updated = await _client
          .from('dev_auth')
          .update({
            'full_name': fullName,
            'email': email,
            'profile_complete': true,
          })
          .eq('phone', phone)
          .select();

      debugPrint('[DODO][Profile] Supabase update raw response: $updated');

      if ((updated as List).isEmpty) {
        debugPrint(
          '[DODO][Profile] Supabase update failed: 0 rows updated — '
          'phone=$phone not found in dev_auth or RLS blocked write',
        );
        throw Exception(
          'Profile update failed: no matching row in dev_auth for phone $phone',
        );
      }

      // Verify by re-reading the row.
      final verified = await _client
          .from('dev_auth')
          .select('phone, full_name, email, profile_complete')
          .eq('phone', phone)
          .single();
      debugPrint('[DODO][Profile] Supabase update success — verified row: $verified');
      debugPrint('[DODO][Auth] Profile Completed');

      // ── 2. Sync customers table ────────────────────────────────────────────
      await _syncCustomerProfile(
        phone: phone,
        fullName: fullName,
        email: email,
      );
    } catch (e) {
      debugPrint('[DODO][Profile] Supabase update failed: $e');
      rethrow;
    }
  }

  // ── Session restore ────────────────────────────────────────────────────────

  /// Called on app startup to re-register the FCM token for an existing session.
  /// No-ops when no session exists or customerId is absent (legacy sessions).
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

  /// Clears the local session.
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
  }
}
