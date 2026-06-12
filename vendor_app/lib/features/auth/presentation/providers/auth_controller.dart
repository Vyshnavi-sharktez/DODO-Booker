import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/supabase_client_provider.dart';
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
      state = user != null
          ? AuthAuthenticated(user: user)
          : const AuthUnauthenticated();
    } catch (_) {
      state = const AuthUnauthenticated();
    }
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
      state = AuthError(message: e.toString());
    }
  }

  Future<void> verifyOtp({required String phone, required String token}) async {
    state = const AuthLoading();
    try {
      final user = await _repository.verifyOtp(phone: phone, token: token);
      state = AuthAuthenticated(user: user);
    } catch (e) {
      state = AuthError(message: e.toString());
    }
  }

  Future<void> signOut() async {
    state = const AuthLoading();
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
