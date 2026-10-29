// Tests for vendor deactivation enforcement in the auth layer.
//
// These are unit tests for the pure-Dart logic in AuthController and AuthState.
// They use a fake IAuthRepository so no network or Supabase connection is needed.
//
// DB-level enforcement (triggers, RLS policies) is verified by the comments
// in the migration file; SQL tests would require a live Postgres instance which
// is outside the scope of the Flutter test suite.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vendor_app/features/auth/domain/entities/vendor_user.dart';
import 'package:vendor_app/features/auth/domain/repositories/i_auth_repository.dart';
import 'package:vendor_app/features/auth/presentation/providers/auth_controller.dart';
import 'package:vendor_app/features/auth/presentation/providers/auth_state.dart';

// ── Fake repository ────────────────────────────────────────────────────────────

class _FakeAuthRepository implements IAuthRepository {
  VendorUser? currentUser;
  bool signedOut = false;

  @override
  Future<VendorUser?> getCurrentUser() async => currentUser;

  @override
  Future<void> signInWithOtp(String phone) async {}

  @override
  Future<VendorUser> verifyOtp(
          {required String phone, required String token}) async =>
      throw UnimplementedError();

  @override
  Future<void> signOut() async {
    signedOut = true;
    currentUser = null;
  }

  @override
  Stream<VendorUser?> authStateChanges() async* {
    yield currentUser;
  }
}

// ── Helpers ────────────────────────────────────────────────────────────────────

VendorUser _vendor({required bool isActive}) => VendorUser(
      id: 'vendor-1',
      phone: '+911234567890',
      name: 'Test Vendor',
      isActive: isActive,
      userType: 'vendor',
    );

ProviderContainer _makeContainer(_FakeAuthRepository repo) {
  return ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(repo),
    ],
  );
}

/// Waits until the auth state exits AuthLoading / AuthInitial.
Future<void> _waitForRestore(ProviderContainer container) async {
  for (var i = 0; i < 50; i++) {
    final s = container.read(authControllerProvider);
    if (s is! AuthLoading && s is! AuthInitial) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

// ── Tests ──────────────────────────────────────────────────────────────────────

void main() {
  group('AuthController — session restore', () {
    test('active vendor → AuthAuthenticated', () async {
      final repo = _FakeAuthRepository()..currentUser = _vendor(isActive: true);
      final container = _makeContainer(repo);
      addTearDown(container.dispose);

      // Wait for _restoreSession to complete.
      await _waitForRestore(container);

      final state = container.read(authControllerProvider);
      expect(state, isA<AuthAuthenticated>());
      expect((state as AuthAuthenticated).user.isActive, isTrue);
    });

    test('inactive vendor → AuthAccountInactive (not AuthAuthenticated)', () async {
      final repo = _FakeAuthRepository()
        ..currentUser = _vendor(isActive: false);
      final container = _makeContainer(repo);
      addTearDown(container.dispose);

      await _waitForRestore(container);

      expect(container.read(authControllerProvider), isA<AuthAccountInactive>());
    });

    test('no saved session → AuthUnauthenticated', () async {
      final repo = _FakeAuthRepository(); // currentUser = null
      final container = _makeContainer(repo);
      addTearDown(container.dispose);

      await _waitForRestore(container);

      expect(container.read(authControllerProvider), isA<AuthUnauthenticated>());
    });
  });

  group('AuthController — recheckActiveStatus', () {
    test('active → inactive transition sets AuthAccountInactive without signing out',
        () async {
      final repo = _FakeAuthRepository()
        ..currentUser = _vendor(isActive: true);
      final container = _makeContainer(repo);
      addTearDown(container.dispose);

      // Wait for initial restore to AuthAuthenticated.
      await _waitForRestore(container);
      expect(container.read(authControllerProvider), isA<AuthAuthenticated>());

      // Simulate admin deactivating the vendor.
      repo.currentUser = _vendor(isActive: false);
      await container
          .read(authControllerProvider.notifier)
          .recheckActiveStatus();

      expect(container.read(authControllerProvider), isA<AuthAccountInactive>());
      // Phone is NOT cleared — kept so reactivation restores access seamlessly.
      expect(repo.signedOut, isFalse);
      // vendorId is stored in the inactive state for the Realtime status channel.
      final inactive =
          container.read(authControllerProvider) as AuthAccountInactive;
      expect(inactive.vendorId, equals('vendor-1'));
    });

    test('inactive → active transition (reactivation) restores AuthAuthenticated',
        () async {
      final repo = _FakeAuthRepository()
        ..currentUser = _vendor(isActive: false);
      final container = _makeContainer(repo);
      addTearDown(container.dispose);

      await _waitForRestore(container);
      expect(container.read(authControllerProvider), isA<AuthAccountInactive>());

      // Simulate admin reactivating the vendor.
      repo.currentUser = _vendor(isActive: true);
      await container
          .read(authControllerProvider.notifier)
          .recheckActiveStatus();

      final state = container.read(authControllerProvider);
      expect(state, isA<AuthAuthenticated>());
      expect((state as AuthAuthenticated).user.isActive, isTrue);
    });

    test('recheck when already active makes no state change', () async {
      final repo = _FakeAuthRepository()
        ..currentUser = _vendor(isActive: true);
      final container = _makeContainer(repo);
      addTearDown(container.dispose);

      await _waitForRestore(container);

      final before = container.read(authControllerProvider);
      await container
          .read(authControllerProvider.notifier)
          .recheckActiveStatus();
      final after = container.read(authControllerProvider);

      // State object should still be AuthAuthenticated; user unchanged.
      expect(after, isA<AuthAuthenticated>());
      expect((after as AuthAuthenticated).user.id,
          equals((before as AuthAuthenticated).user.id));
    });

    test('recheck when session disappears → AuthUnauthenticated', () async {
      final repo = _FakeAuthRepository()
        ..currentUser = _vendor(isActive: true);
      final container = _makeContainer(repo);
      addTearDown(container.dispose);

      await _waitForRestore(container);

      // Session removed (e.g. SharedPreferences cleared externally).
      repo.currentUser = null;
      await container
          .read(authControllerProvider.notifier)
          .recheckActiveStatus();

      expect(
          container.read(authControllerProvider), isA<AuthUnauthenticated>());
    });
  });

  group('AuthController — dodo_team members never go inactive', () {
    test('dodo_team with isActive=false is still AuthAuthenticated', () async {
      final dodoTeamUser = VendorUser(
        id: 'team-1',
        phone: '+919999999999',
        isActive: false,
        userType: 'dodo_team',
        dodoTeamId: 'team-1',
      );
      final repo = _FakeAuthRepository()..currentUser = dodoTeamUser;
      final container = _makeContainer(repo);
      addTearDown(container.dispose);

      await _waitForRestore(container);

      // dodo_team members use a different is_active column (dodo_teams.is_active)
      // and are not subject to vendor deactivation flow.
      expect(container.read(authControllerProvider), isA<AuthAuthenticated>());
    });
  });
}
