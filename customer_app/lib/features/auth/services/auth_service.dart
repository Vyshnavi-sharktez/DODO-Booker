import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  static const _phoneKey = 'dodo_auth_phone';
  final SupabaseClient _client = Supabase.instance.client;

  // ── Phone check ────────────────────────────────────────────────────────────

  /// Checks that [phone] exists in dev_auth. Throws if not registered.
  Future<void> checkPhone(String phone) async {
    debugPrint('[DODO][Auth] Phone entered: $phone');
    debugPrint('[DODO][Auth] Table: dev_auth');
    debugPrint('[DODO][Auth] Column queried: phone');

    final row = await _client
        .from('dev_auth')
        .select('phone')
        .eq('phone', phone)
        .maybeSingle();

    debugPrint('[DODO][Auth] Query result: $row');

    if (row == null) {
      debugPrint('[DODO][Auth] Phone not found — no row matched phone=$phone in dev_auth');
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

    // Ensure customer record exists — non-fatal if it fails (auth itself succeeded).
    try {
      await _ensureCustomerExists(phone);
    } catch (e) {
      debugPrint('[DODO][Customer] Warning: could not sync customer record after login: $e');
    }
  }

  // ── Customer record ────────────────────────────────────────────────────────

  /// Checks if a customer exists for [phone]; inserts a placeholder row if not.
  Future<void> _ensureCustomerExists(String phone) async {
    debugPrint('[DODO][Customer] Checking customers table for phone=$phone');

    final existing = await _client
        .from('customers')
        .select('id, phone, full_name')
        .eq('phone', phone)
        .maybeSingle();

    if (existing != null) {
      debugPrint('[DODO][Customer] Customer found: id=${existing['id']}');
      return;
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
        .select('id, phone')
        .single();
    debugPrint('[DODO][Customer] Customer created successfully: id=${created['id']}');
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

  // ── Sign out ───────────────────────────────────────────────────────────────

  /// Clears the local session.
  Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_phoneKey);
  }
}
