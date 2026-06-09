import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/models/admin_user.dart';

class AuthRepository {
  final SupabaseClient _supabase;

  const AuthRepository(this._supabase);

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    return await _supabase.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<void> signOut() async {
    await _supabase.auth.signOut();
  }

  Future<AdminUser> fetchAdminUser(String userId) async {
    // 1. Fetch admin_users row by auth_user_id
    Map<String, dynamic>? adminRow;
    Object? adminError;
    try {
      adminRow = await _supabase
          .from('admin_users')
          .select()
          .eq('auth_user_id', userId)
          .eq('is_active', true)
          .single();
    } catch (e) {
      adminError = e;
    }

    if (adminError != null || adminRow == null) {
      if (adminError != null) throw adminError;
      throw Exception('No active admin_users row for auth_user_id=$userId');
    }

    final adminId = adminRow['id'] as String;
    final isSuperAdminColumn = adminRow['is_super_admin'] as bool? ?? false;

    // 2. Update last_login_at — best-effort, skip if column absent
    try {
      await _supabase
          .from('admin_users')
          .update({'last_login_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', adminId);
    } catch (_) {}

    // 3. Super admin column fast-path
    if (isSuperAdminColumn) {
      return _buildUser(adminRow, adminId, userId,
          isSuperAdmin: true, permissions: const {}, roleNames: ['Super Admin']);
    }

    // 4. Fetch assigned roles
    List<dynamic> rolesList = [];
    try {
      rolesList = await _supabase
          .from('admin_user_roles')
          .select('role_id, roles(id, name)')
          .eq('admin_user_id', adminId);
    } catch (e) {
      rethrow;
    }

    final roleIds = rolesList.map((r) => r['role_id'] as String).toList();
    final roleNames = rolesList
        .map((r) {
          final role = r['roles'] as Map<String, dynamic>?;
          return role?['name'] as String? ?? '';
        })
        .where((n) => n.isNotEmpty)
        .toList();

    // Super admin fallback: check role name when column is not set
    final isSuperAdminByRole = roleNames.any((name) {
      final n = name.toLowerCase().trim();
      return n == 'super admin' || n == 'superadmin' || n == 'super_admin';
    });

    if (isSuperAdminByRole) {
      return _buildUser(adminRow, adminId, userId,
          isSuperAdmin: true,
          permissions: const {},
          roleNames: roleNames.isEmpty ? ['Super Admin'] : roleNames);
    }

    if (roleIds.isEmpty) {
      return _buildUser(adminRow, adminId, userId,
          isSuperAdmin: false, permissions: const {}, roleNames: const []);
    }

    // 5. Fetch permissions via role_permissions join
    List<dynamic> permsData = [];
    try {
      permsData = await _supabase
          .from('role_permissions')
          .select('permissions(name)')
          .inFilter('role_id', roleIds);
    } catch (e) {
      rethrow;
    }

    final permissionNames = permsData
        .map((p) {
          final perms = p['permissions'];
          if (perms == null) return null;
          return (perms as Map<String, dynamic>)['name'] as String?;
        })
        .whereType<String>()
        .toSet();

    return _buildUser(adminRow, adminId, userId,
        isSuperAdmin: false,
        permissions: permissionNames,
        roleNames: roleNames);
  }

  AdminUser _buildUser(
    Map<String, dynamic> row,
    String adminId,
    String userId, {
    required bool isSuperAdmin,
    required Set<String> permissions,
    required List<String> roleNames,
  }) {
    return AdminUser(
      id: adminId,
      userId: userId,
      fullName: row['full_name'] as String? ?? '',
      email: row['email'] as String? ?? '',
      isSuperAdmin: isSuperAdmin,
      isActive: true,
      permissions: permissions,
      roleNames: roleNames,
    );
  }
}
