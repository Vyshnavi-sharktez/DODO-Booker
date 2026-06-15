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
    await _datasource.verifyOtp(phone: phone, otp: token);
    await _datasource.savePhone(phone);
    final vendorRow = await _datasource.getVendorByPhone(phone);
    if (vendorRow == null) return VendorUserModel.fromPhone(phone);
    return VendorUserModel.fromVendorRow(row: vendorRow, phone: phone);
  }

  @override
  Future<VendorUser?> getCurrentUser() async {
    final phone = await _datasource.getSavedPhone();
    debugPrint('[AUTH] getCurrentUser — savedPhone : ${phone == null ? "NULL (no session)" : '"$phone" (len=${phone.length})'}');
    if (phone == null) return null;
    final vendorRow = await _datasource.getVendorByPhone(phone);
    if (vendorRow == null) {
      debugPrint('[AUTH] getCurrentUser — vendor row NOT found, using phone as id');
      return VendorUserModel.fromPhone(phone);
    }
    debugPrint('[AUTH] getCurrentUser — vendor row FOUND id=${vendorRow['id']}');
    return VendorUserModel.fromVendorRow(row: vendorRow, phone: phone);
  }

  @override
  Future<void> signOut() => _datasource.clearSession();

  @override
  Stream<VendorUser?> authStateChanges() async* {
    yield await getCurrentUser();
  }
}
