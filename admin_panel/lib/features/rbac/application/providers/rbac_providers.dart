import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../auth/application/providers/auth_provider.dart';
import '../../data/rbac_repository.dart';
import '../../domain/models/permission.dart';
import '../../domain/models/rbac_admin_user.dart';
import '../../domain/models/role.dart';

// ── Repository ────────────────────────────────────────────────────────────────

final rbacRepositoryProvider = Provider<RbacRepository>((ref) {
  return RbacRepository(ref.watch(supabaseClientProvider));
});

// ── Read providers ─────────────────────────────────────────────────────────────

final rolesProvider = FutureProvider<List<Role>>((ref) {
  return ref.watch(rbacRepositoryProvider).fetchRoles();
});

final permissionsProvider = FutureProvider<List<Permission>>((ref) {
  return ref.watch(rbacRepositoryProvider).fetchPermissions();
});

final rbacAdminUsersProvider = FutureProvider<List<RbacAdminUser>>((ref) {
  return ref.watch(rbacRepositoryProvider).fetchAdminUsers();
});

// ── Roles notifier ─────────────────────────────────────────────────────────────

class RolesNotifier extends StateNotifier<AsyncValue<List<Role>>> {
  final RbacRepository _repo;
  final Ref _ref;

  RolesNotifier(this._repo, this._ref) : super(const AsyncValue.loading()) {
    _load();
  }

  Future<void> _load() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_repo.fetchRoles);
    _ref.invalidate(rolesProvider);
  }

  Future<void> refresh() => _load();

  Future<void> createRole({
    required String name,
    String? description,
  }) async {
    await _repo.createRole(name: name, description: description);
    await _load();
  }

  Future<void> updateRole(
    String id, {
    String? name,
    String? description,
    bool? isActive,
  }) async {
    await _repo.updateRole(
      id,
      name: name,
      description: description,
      isActive: isActive,
    );
    await _load();
  }

  Future<void> deleteRole(String id) async {
    await _repo.deleteRole(id);
    await _load();
  }

  Future<void> setRolePermissions(
    String roleId,
    List<String> permissionIds,
  ) async {
    await _repo.setRolePermissions(roleId, permissionIds);
    await _load();
  }
}

final rolesNotifierProvider =
    StateNotifierProvider<RolesNotifier, AsyncValue<List<Role>>>((ref) {
  return RolesNotifier(
    ref.watch(rbacRepositoryProvider),
    ref,
  );
});

// ── Admin Users notifier ───────────────────────────────────────────────────────

class RbacAdminUsersNotifier
    extends StateNotifier<AsyncValue<List<RbacAdminUser>>> {
  final RbacRepository _repo;
  final Ref _ref;

  RbacAdminUsersNotifier(this._repo, this._ref)
      : super(const AsyncValue.loading()) {
    _load();
  }

  Future<void> _load() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_repo.fetchAdminUsers);
    _ref.invalidate(rbacAdminUsersProvider);
  }

  Future<void> refresh() => _load();

  Future<void> setAdminUserRoles(
    String adminUserId,
    List<String> roleIds,
  ) async {
    await _repo.setAdminUserRoles(adminUserId, roleIds);
    await _load();
  }

  Future<void> updateAdminUser(
    String id, {
    String? fullName,
    bool? isActive,
  }) async {
    await _repo.updateAdminUser(id, fullName: fullName, isActive: isActive);
    await _load();
  }
}

final rbacAdminUsersNotifierProvider = StateNotifierProvider<
    RbacAdminUsersNotifier, AsyncValue<List<RbacAdminUser>>>((ref) {
  return RbacAdminUsersNotifier(
    ref.watch(rbacRepositoryProvider),
    ref,
  );
});

// ── Permissions grouped by module ──────────────────────────────────────────────

final permissionsByModuleProvider =
    Provider<Map<String, List<Permission>>>((ref) {
  final permissionsAsync = ref.watch(permissionsProvider);
  return permissionsAsync.whenOrNull(
        data: (perms) {
          final map = <String, List<Permission>>{};
          for (final p in perms) {
            map.putIfAbsent(p.module, () => []).add(p);
          }
          return map;
        },
      ) ??
      {};
});
