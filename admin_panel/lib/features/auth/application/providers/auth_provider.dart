import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
