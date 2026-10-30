import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import '../../../../core/network/supabase_client_provider.dart';
import '../../../../core/services/fcm_service.dart';
import '../../data/datasources/auth_remote_datasource.dart';
import '../../data/repositories/auth_repository_impl.dart';
import '../../domain/entities/vendor_user.dart';
import '../../domain/repositories/i_auth_repository.dart';
import 'auth_state.dart';

final authDatasourceProvider = Provider<AuthRemoteDatasource>((ref) {
  return AuthRemoteDatasource(ref.watch(supabaseClientProvider));
});

final authRepositoryProvider = Provider<IAuthRepository>((ref) {
  return AuthRepositoryImpl(ref.watch(authDatasourceProvider));
});

class AuthController extends StateNotifier<AuthState> {
  AuthController(this._repository) : super(const AuthInitial()) {
    _restoreSession();
  }

  final IAuthRepository _repository;

  Future<void> _restoreSession() async {
    state = const AuthLoading();
    try {
      final user = await _repository.getCurrentUser();
      if (user != null) {
        if (!user.isActive && user.userType == 'vendor') {
          // Do NOT sign out — keep the phone in SharedPreferences so that
          // reactivation can restore access without a new OTP. The DB triggers
          // and RLS policies block all sensitive writes while inactive.
          state = AuthAccountInactive(vendorId: user.id);
        } else {
          state = AuthAuthenticated(user: user);
          _initFcm(user);
        }
      } else {
        state = const AuthUnauthenticated();
      }
    } catch (_) {
      state = const AuthUnauthenticated();
    }
  }

  /// Re-fetches the vendor record and re-evaluates active status.
  /// Called on app resume and by the Realtime vendor-status channel.
  Future<void> recheckActiveStatus() async {
    final current = state;
    if (current is! AuthAuthenticated && current is! AuthAccountInactive) return;

    try {
      final user = await _repository.getCurrentUser();
      if (user == null) {
        // Session cleared externally (e.g. explicit sign-out from inactive screen).
        state = const AuthUnauthenticated();
        return;
      }
      if (!user.isActive && user.userType == 'vendor') {
        if (current is AuthAuthenticated) {
          // Newly deactivated — transition without signing out so the phone
          // remains in SharedPreferences for seamless reactivation.
          state = AuthAccountInactive(vendorId: user.id);
        }
        // Already inactive — no state change needed.
      } else {
        if (current is AuthAccountInactive) {
          // Reactivated: re-validate identity then restore full access.
          state = AuthAuthenticated(user: user);
          _initFcm(user);
        }
        // Already authenticated — no change needed.
      }
    } catch (_) {
      // Network error during resume check — keep current state.
    }
  }

  void _initFcm(VendorUser user) {
    // Only register FCM for actual vendors (not dodo_team members)
    if (user.userType != 'vendor') return;
    VendorFcmService.initialize(user.id, user.phone).catchError((_) {});
  }

  Future<void> sendOtp(String phone) async {
    debugPrint('[DODO][AuthController] sendOtp received : "$phone"');
    debugPrint('[DODO][AuthController] length           : ${phone.length}');
    debugPrint('[DODO][AuthController] codeUnits        : ${phone.codeUnits}');
    state = const AuthLoading();
    try {
      await _repository.signInWithOtp(phone);
      state = AuthOtpSent(phone: phone);
    } catch (e) {
      debugPrint('[DODO][AuthController] sendOtp error: $e');
      state = AuthError(message: _sendOtpError(e));
    }
  }

  Future<void> verifyOtp({required String phone, required String token}) async {
    state = const AuthLoading();
    try {
      final user = await _repository.verifyOtp(phone: phone, token: token);
      if (!user.isActive && user.userType == 'vendor') {
        state = AuthAccountInactive(vendorId: user.id);
      } else {
        state = AuthAuthenticated(user: user);
        _initFcm(user);
      }
    } catch (e) {
      state = AuthError(message: _otpErrorMessage(e));
    }
  }

  String _otpErrorMessage(Object e) {
    if (e is AuthException) {
      if (e.code == 'otp_expired') return 'OTP has expired. Please request a new OTP.';
      if (e.code == 'over_sms_send_rate_limit') return 'Too many attempts. Please wait before requesting a new OTP.';
      return 'Invalid OTP. Please try again.';
    }
    return 'Something went wrong. Please try again.';
  }

  String _sendOtpError(Object e) {
    if (e is AuthException) {
      if (e.code == 'over_sms_send_rate_limit') return 'Too many OTP requests. Please wait and try again.';
      if (e.code == 'sms_send_failed') return 'Unable to send OTP. Please check your number.';
      return 'Failed to send OTP. Please try again.';
    }
    return 'Something went wrong. Please try again.';
  }

  Future<void> signOut() async {
    final currentUser =
        state is AuthAuthenticated ? (state as AuthAuthenticated).user : null;
    state = const AuthLoading();
    if (currentUser != null && currentUser.userType == 'vendor') {
      try {
        await VendorFcmService.clearToken(currentUser.id, currentUser.phone);
      } catch (_) {}
    }
    try {
      await _repository.signOut();
      state = const AuthUnauthenticated();
    } catch (e) {
      state = AuthError(message: e.toString());
    }
  }
}

final authControllerProvider =
    StateNotifierProvider<AuthController, AuthState>(
  (ref) => AuthController(ref.watch(authRepositoryProvider)),
);

final authStateProvider = Provider<AuthState>(
  (ref) => ref.watch(authControllerProvider),
);

final currentVendorUserProvider = Provider<VendorUser?>(
  (ref) {
    final state = ref.watch(authControllerProvider);
    return state is AuthAuthenticated ? state.user : null;
  },
);
