import 'package:flutter/foundation.dart';
import '../../domain/entities/vendor_user.dart';
import '../../domain/repositories/i_auth_repository.dart';
import '../datasources/auth_remote_datasource.dart';
import '../models/vendor_user_model.dart';

class AuthRepositoryImpl implements IAuthRepository {
  const AuthRepositoryImpl(this._datasource);
  final AuthRemoteDatasource _datasource;

  @override
  Future<void> signInWithOtp(String phone) =>
      _datasource.checkPhone(phone);

  @override
  Future<VendorUser> verifyOtp({
    required String phone,
    required String token,
  }) async {
    // 1. Verify OTP via Supabase Auth (throws on invalid/expired OTP)
    await _datasource.verifyOtp(phone: phone, otp: token);

    // 2. Persist session phone
    await _datasource.savePhone(phone);

    // 3. Resolve user — check dodo_teams first (they never get a vendor record)
    final dodoRow = await _datasource.getDodoTeamByPhone(phone);
    if (dodoRow != null) {
      debugPrint('[AUTH] verifyOtp — DODO team user FOUND id=${dodoRow['id']}');
      return VendorUserModel.fromDodoTeamRow(row: dodoRow, phone: phone);
    }

    // 4. For vendors (existing or brand-new): ensure_vendor_created links or creates
    try {
      await _datasource.ensureVendorCreated(phone);
    } catch (e) {
      debugPrint('[AUTH] ensureVendorCreated warning: $e');
    }

    return _resolveUser(phone);
  }

  @override
  Future<VendorUser?> getCurrentUser() async {
    final phone = await _datasource.getSavedPhone();
    debugPrint('[AUTH] getCurrentUser — savedPhone : ${phone == null ? "NULL (no session)" : '"$phone" (len=${phone.length})'}');
    if (phone == null) return null;
    return _resolveUser(phone);
  }

  // Resolves a phone to a VendorUser: checks vendors then dodo_teams.
  // Used for session restore — does not create new records.
  Future<VendorUser> _resolveUser(String phone) async {
    final vendorRow = await _datasource.getVendorByPhone(phone);
    if (vendorRow != null) {
      debugPrint('[AUTH] _resolveUser — vendor row FOUND id=${vendorRow['id']}');
      return VendorUserModel.fromVendorRow(row: vendorRow, phone: phone);
    }
    final dodoRow = await _datasource.getDodoTeamByPhone(phone);
    if (dodoRow != null) {
      debugPrint('[AUTH] _resolveUser — DODO team row FOUND id=${dodoRow['id']}');
      return VendorUserModel.fromDodoTeamRow(row: dodoRow, phone: phone);
    }
    debugPrint('[AUTH] _resolveUser — no row found, using phone as id');
    return VendorUserModel.fromPhone(phone);
  }

  @override
  Future<void> signOut() => _datasource.clearSession();

  @override
  Stream<VendorUser?> authStateChanges() async* {
    yield await getCurrentUser();
  }
}
