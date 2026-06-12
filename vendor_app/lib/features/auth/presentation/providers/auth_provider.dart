import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/network/supabase_client_provider.dart';
import '../../data/auth_repository.dart';
import '../../domain/models/vendor_auth_state.dart';

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(supabaseClientProvider)),
);

class AuthNotifier extends StateNotifier<VendorAuthState> {
  AuthNotifier(this._repo) : super(const VendorAuthState());

  final AuthRepository _repo;

  Future<void> sendOtp(String phone) async {}

  Future<void> verifyOtp({
    required String phone,
    required String token,
  }) async {}

  Future<void> signOut() async {}
}

final authNotifierProvider =
    StateNotifierProvider<AuthNotifier, VendorAuthState>(
  (ref) => AuthNotifier(ref.watch(authRepositoryProvider)),
);

final currentSessionProvider = Provider<Session?>(
  (ref) => ref.watch(authNotifierProvider).session,
);
