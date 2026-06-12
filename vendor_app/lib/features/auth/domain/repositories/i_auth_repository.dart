import '../entities/vendor_user.dart';

abstract interface class IAuthRepository {
  Future<void> signInWithOtp(String phone);
  Future<VendorUser> verifyOtp({required String phone, required String token});
  Future<VendorUser?> getCurrentUser();
  Future<void> signOut();
  Stream<VendorUser?> authStateChanges();
}
