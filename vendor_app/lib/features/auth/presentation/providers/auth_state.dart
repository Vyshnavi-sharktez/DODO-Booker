import '../../domain/entities/vendor_user.dart';

sealed class AuthState {
  const AuthState();
}

final class AuthInitial extends AuthState {
  const AuthInitial();
}

final class AuthLoading extends AuthState {
  const AuthLoading();
}

final class AuthOtpSent extends AuthState {
  const AuthOtpSent({required this.phone});
  final String phone;
}

final class AuthAuthenticated extends AuthState {
  const AuthAuthenticated({required this.user});
  final VendorUser user;
}

final class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated();
}

final class AuthError extends AuthState {
  const AuthError({required this.message});
  final String message;
}
