import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../shared/repositories/base_repository.dart';

class AuthRepository extends BaseRepository {
  const AuthRepository(super.supabase);

  Future<void> sendOtp(String phone) async {}

  Future<AuthResponse> verifyOtp({
    required String phone,
    required String token,
  }) async => throw UnimplementedError();

  Future<void> signOut() async {}

  Session? get currentSession => supabase.auth.currentSession;
}
