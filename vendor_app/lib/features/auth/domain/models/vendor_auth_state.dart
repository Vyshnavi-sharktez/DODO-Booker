import 'package:supabase_flutter/supabase_flutter.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

class VendorAuthState {
  const VendorAuthState({
    this.status = AuthStatus.unknown,
    this.session,
    this.vendorId,
  });

  final AuthStatus status;
  final Session? session;
  final String? vendorId;

  bool get isAuthenticated => status == AuthStatus.authenticated;

  VendorAuthState copyWith({
    AuthStatus? status,
    Session? session,
    String? vendorId,
  }) {
    return VendorAuthState(
      status: status ?? this.status,
      session: session ?? this.session,
      vendorId: vendorId ?? this.vendorId,
    );
  }
}
