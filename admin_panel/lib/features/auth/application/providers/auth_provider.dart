import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/config/app_url_config.dart';
import '../../data/auth_repository.dart';
import '../../domain/models/admin_user.dart';

// ── Core Supabase client ───────────────────────────────────────────────────────

final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

// ── Auth repository ────────────────────────────────────────────────────────────

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(supabaseClientProvider));
});

// ── Auth state stream (Supabase session events) ────────────────────────────────

final authStateProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(supabaseClientProvider).auth.onAuthStateChange;
});

// ── Admin user data (fetched after login) ─────────────────────────────────────
// Rebuilds whenever auth state changes. Returns null when logged out.

final adminUserProvider = StreamProvider<AdminUser?>((ref) {
  final authStream = ref.watch(supabaseClientProvider).auth.onAuthStateChange;
  final repo = ref.read(authRepositoryProvider);

  return authStream.asyncMap((authState) async {
    final session = authState.session;
    if (session == null) return null;
    return await repo.fetchAdminUser(session.user.id);
  });
});

// ── Convenience: resolved admin user (or null) ────────────────────────────────

final currentAdminUserProvider = Provider<AdminUser?>((ref) {
  return ref.watch(adminUserProvider).asData?.value;
});

// ── Convenience: is user authenticated ────────────────────────────────────────

final isAuthenticatedProvider = Provider<bool>((ref) {
  final authData = ref.watch(authStateProvider).asData;
  if (authData != null) return authData.value.session != null;
  return Supabase.instance.client.auth.currentSession != null;
});

// ── Login / Logout notifier ────────────────────────────────────────────────────

class AuthNotifier extends StateNotifier<AsyncValue<void>> {
  final AuthRepository _repo;

  AuthNotifier(this._repo) : super(const AsyncValue.data(null));

  Future<void> login({required String email, required String password}) async {
    state = const AsyncValue.loading();
    try {
      await _repo.signIn(email: email, password: password);
      state = const AsyncValue.data(null);
    } on AuthException catch (e, s) {
      state = AsyncValue.error(e.message, s);
    } catch (e, s) {
      state = AsyncValue.error(e.toString(), s);
    }
  }

  Future<void> logout() async {
    state = const AsyncValue.loading();
    try {
      await _repo.signOut();
      state = const AsyncValue.data(null);
    } catch (e, s) {
      state = AsyncValue.error(e.toString(), s);
    }
  }

  void clearError() {
    if (state is AsyncError) {
      state = const AsyncValue.data(null);
    }
  }
}

final authNotifierProvider =
    StateNotifierProvider<AuthNotifier, AsyncValue<void>>((ref) {
  return AuthNotifier(ref.watch(authRepositoryProvider));
});

// ── One-shot success message shown on the login page after a password reset ────

final loginSuccessMessageProvider = StateProvider<String?>((ref) => null);

// ── Forgot Password ────────────────────────────────────────────────────────────

sealed class ForgotPasswordState {
  const ForgotPasswordState();
}

class ForgotPasswordIdle extends ForgotPasswordState {
  const ForgotPasswordIdle();
}

class ForgotPasswordLoading extends ForgotPasswordState {
  const ForgotPasswordLoading();
}

class ForgotPasswordSent extends ForgotPasswordState {
  const ForgotPasswordSent();
}

class ForgotPasswordError extends ForgotPasswordState {
  final String message;
  const ForgotPasswordError(this.message);
}

class ForgotPasswordNotifier
    extends StateNotifier<ForgotPasswordState> {
  final AuthRepository _repo;

  ForgotPasswordNotifier(this._repo) : super(const ForgotPasswordIdle());

  Future<void> sendResetEmail(String email) async {
    // Hard guard: reject concurrent or post-success calls regardless of how
    // many times the method is invoked from the UI layer.
    if (state is ForgotPasswordLoading || state is ForgotPasswordSent) return;
    state = const ForgotPasswordLoading();
    try {
      await _repo.sendPasswordResetEmail(
        email,
        redirectTo: AppUrlConfig.passwordResetRedirectUrl,
      );
      state = const ForgotPasswordSent();
    } on AuthException catch (e) {
      state = ForgotPasswordError(e.message);
    } catch (e) {
      state = ForgotPasswordError('Network error. Please try again.');
    }
  }

  void reset() => state = const ForgotPasswordIdle();
}

final forgotPasswordProvider =
    StateNotifierProvider.autoDispose<ForgotPasswordNotifier, ForgotPasswordState>(
  (ref) => ForgotPasswordNotifier(ref.watch(authRepositoryProvider)),
);

// ── Update Password (used on the Reset Password page) ─────────────────────────

class UpdatePasswordNotifier extends StateNotifier<AsyncValue<void>> {
  final AuthRepository _repo;

  UpdatePasswordNotifier(this._repo) : super(const AsyncValue.data(null));

  Future<void> update(String newPassword) async {
    state = const AsyncValue.loading();
    try {
      await _repo.updatePassword(newPassword);
      state = const AsyncValue.data(null);
    } on AuthException catch (e, s) {
      state = AsyncValue.error(e.message, s);
    } catch (e, s) {
      state = AsyncValue.error('Network error. Please try again.', s);
    }
  }

  void clearError() {
    if (state is AsyncError) state = const AsyncValue.data(null);
  }
}

final updatePasswordProvider =
    StateNotifierProvider.autoDispose<UpdatePasswordNotifier, AsyncValue<void>>(
  (ref) => UpdatePasswordNotifier(ref.watch(authRepositoryProvider)),
);
