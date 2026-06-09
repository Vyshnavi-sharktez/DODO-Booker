import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/models/permission.dart';
import '../domain/models/rbac_admin_user.dart';
import '../domain/models/role.dart';

class RbacRepository {
  final SupabaseClient _supabase;

  const RbacRepository(this._supabase);

  // ── Roles ─────────────────────────────────────────────────────────────────

  Future<List<Role>> fetchRoles() async {
    final data = await _supabase
        .from('roles')
        .select('*, role_permissions(permissions_id)')
        .order('name');
    return (data as List<dynamic>)
        .map((r) => Role.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<Role> createRole({
    required String name,
    String? description,
  }) async {
    final data = await _supabase
        .from('roles')
        .insert({
          'name': name,
          'description': description,
          'is_system': false,
          'is_active': true,
        })
        .select('*, role_permissions(permissions_id)')
        .single();
    return Role.fromMap(data);
  }

  Future<Role> updateRole(
    String id, {
    String? name,
    String? description,
    bool? isActive,
  }) async {
    final updates = <String, dynamic>{};
    if (name != null) updates['name'] = name;
    if (description != null) updates['description'] = description;
    if (isActive != null) updates['is_active'] = isActive;

    final data = await _supabase
        .from('roles')
        .update(updates)
        .eq('id', id)
        .select('*, role_permissions(permissions_id)')
        .single();
    return Role.fromMap(data);
  }

  Future<void> deleteRole(String id) async {
    await _supabase.from('roles').delete().eq('id', id);
  }

  // ── Role-Permission assignments ────────────────────────────────────────────

  Future<void> setRolePermissions(
    String roleId,
    List<String> permissionIds,
  ) async {
    await _supabase
        .from('role_permissions')
        .delete()
        .eq('role_id', roleId);

    if (permissionIds.isEmpty) return;

    await _supabase.from('role_permissions').insert(
          permissionIds
              .map((pid) => {'role_id': roleId, 'permissions_id': pid})
              .toList(),
        );
  }

  // ── Permissions ────────────────────────────────────────────────────────────

  Future<List<Permission>> fetchPermissions() async {
    final data = await _supabase
        .from('permissions')
        .select()
        .order('name', ascending: true);
    return (data as List<dynamic>)
        .map((p) => Permission.fromMap(p as Map<String, dynamic>))
        .toList();
  }

  // ── Admin Users ────────────────────────────────────────────────────────────

  Future<List<RbacAdminUser>> fetchAdminUsers() async {
    final data = await _supabase
        .from('admin_users')
        .select('*, admin_user_roles(role_id, roles(id, name))')
        .order('full_name');
    return (data as List<dynamic>)
        .map((u) => RbacAdminUser.fromMap(u as Map<String, dynamic>))
        .toList();
  }

  Future<RbacAdminUser> updateAdminUser(
    String id, {
    String? fullName,
    bool? isActive,
  }) async {
    final updates = <String, dynamic>{};
    if (fullName != null) updates['full_name'] = fullName;
    if (isActive != null) updates['is_active'] = isActive;

    final data = await _supabase
        .from('admin_users')
        .update(updates)
        .eq('id', id)
        .select('*, admin_user_roles(role_id, roles(id, name))')
        .single();
    return RbacAdminUser.fromMap(data);
  }

  Future<void> setAdminUserRoles(
    String adminUserId,
    List<String> roleIds,
  ) async {
    await _supabase
        .from('admin_user_roles')
        .delete()
        .eq('admin_user_id', adminUserId);

    if (roleIds.isEmpty) return;

    await _supabase.from('admin_user_roles').insert(
          roleIds
              .map((rid) => {'admin_user_id': adminUserId, 'role_id': rid})
              .toList(),
        );
  }
}
