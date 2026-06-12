import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/config/supabase_config.dart';
import '../../../models/profile_model.dart';

class ProfileService {
  static bool get _ready =>
      SupabaseConfig.supabaseUrl.isNotEmpty &&
      SupabaseConfig.supabaseAnonKey.isNotEmpty;

  static SupabaseClient get _db => Supabase.instance.client;

  static const _phoneKey = 'dodo_auth_phone';

  Future<String?> _currentPhone() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_phoneKey);
  }

  // ── Fetch profile ──────────────────────────────────────────────────────────

  Future<ProfileModel> fetchProfile() async {
    if (!_ready) {
      debugPrint('[DODO][ProfileService] fetchProfile → MOCK (Supabase not configured)');
      await Future.delayed(const Duration(milliseconds: 400));
      return _devProfile;
    }
    final phone = await _currentPhone();
    if (phone == null) {
      debugPrint('[DODO][ProfileService] fetchProfile → MOCK (no session)');
      return _devProfile;
    }
    debugPrint('[DODO][ProfileService] fetchProfile → SUPABASE (table: customers, phone: $phone)');
    final data = await _db
        .from('customers')
        .select()
        .eq('phone', phone)
        .single();
    return ProfileModel.fromJson(data);
  }

  // ── Update profile ─────────────────────────────────────────────────────────

  Future<ProfileModel> updateProfile({
    required String fullName,
    String? email,
    String? imageUrl,
  }) async {
    if (!_ready) {
      debugPrint('[DODO][ProfileService] updateProfile → MOCK (Supabase not configured)');
      await Future.delayed(const Duration(milliseconds: 800));
      return _devProfile.copyWith(fullName: fullName, email: email, imageUrl: imageUrl);
    }
    final phone = await _currentPhone();
    if (phone == null) throw Exception('Not authenticated.');
    debugPrint('[DODO][ProfileService] updateProfile → SUPABASE (table: customers UPDATE)');
    final payload = <String, dynamic>{'full_name': fullName};
    if (email != null) payload['email'] = email;
    if (imageUrl != null) payload['profile_image_url'] = imageUrl;
    final data = await _db
        .from('customers')
        .update(payload)
        .eq('phone', phone)
        .select()
        .single();
    return ProfileModel.fromJson(data);
  }
}

// ── Dev fallback profile ──────────────────────────────────────────────────────

const _devProfile = ProfileModel(
  id: 'dev-user-1',
  fullName: 'Amara Patel',
  mobileNumber: '+91 98765 43210',
  email: 'amara.patel@example.com',
  totalBookings: 12,
  completedBookings: 9,
  savedAmount: 1840,
  favouriteCount: 4,
);
