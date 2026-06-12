import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/auth_service.dart';

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

/// Reactive auth state. Initialised from SharedPreferences on first read.
class AuthNotifier extends StateNotifier<bool> {
  final AuthService _service;

  AuthNotifier(this._service) : super(false) {
    _init();
  }

  Future<void> _init() async {
    state = await _service.isAuthenticated();
  }

  void setAuthenticated(bool value) => state = value;
}

final authNotifierProvider = StateNotifierProvider<AuthNotifier, bool>(
  (ref) => AuthNotifier(ref.read(authServiceProvider)),
);

/// Synchronous bool for use with ref.read() in booking_gate.
final isAuthenticatedProvider = Provider<bool>(
  (ref) => ref.watch(authNotifierProvider),
);
