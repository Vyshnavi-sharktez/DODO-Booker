import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../application/providers/rbac_providers.dart';
import '../../domain/models/rbac_admin_user.dart';
import '../../domain/models/role.dart';

class AdminUsersTab extends ConsumerWidget {
  const AdminUsersTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usersAsync = ref.watch(rbacAdminUsersNotifierProvider);
    final rolesAsync = ref.watch(rolesProvider);

    return usersAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline_rounded,
                color: AppColors.error, size: 40),
            const SizedBox(height: 12),
            Text(e.toString(),
                style: TextStyle(color: AppColors.textSecondary),
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () =>
                  ref.read(rbacAdminUsersNotifierProvider.notifier).refresh(),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
      data: (users) => _UsersView(
        users: users,
        allRoles: rolesAsync.valueOrNull ?? [],
      ),
    );
  }
}

class _UsersView extends StatelessWidget {
  const _UsersView({required this.users, required this.allRoles});
  final List<RbacAdminUser> users;
  final List<Role> allRoles;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            children: [
              Text(
                'Admin Users',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(width: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${users.length} users',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color: AppColors.warning.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.info_outline_rounded,
                        size: 14, color: AppColors.warning),
                    const SizedBox(width: 6),
                    Text(
                      'Create users via Supabase Auth',
                      style: TextStyle(
                        color: AppColors.warning,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: users.isEmpty
              ? const Center(child: Text('No admin users found.'))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  itemCount: users.length,
                  separatorBuilder: (_, i) => const SizedBox(height: 8),
                  itemBuilder: (context, i) => _UserCard(
                    user: users[i],
                    allRoles: allRoles,
                  ),
                ),
        ),
      ],
    );
  }
}

class _UserCard extends ConsumerWidget {
  const _UserCard({required this.user, required this.allRoles});
  final RbacAdminUser user;
  final List<Role> allRoles;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Avatar
            CircleAvatar(
              radius: 22,
              backgroundColor: AppColors.primary.withValues(alpha: 0.1),
              child: Text(
                user.displayName.isNotEmpty
                    ? user.displayName[0].toUpperCase()
                    : '?',
                style: TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ),
            const SizedBox(width: 16),

            // Name + email + roles
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          user.displayName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (user.isSuperAdmin)
                        _StatusChip(
                            label: 'Super Admin',
                            color: AppColors.accent),
                      if (!user.isActive)
                        _StatusChip(
                            label: 'Inactive', color: AppColors.error),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    user.email,
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 12),
                  ),
                  if (user.roleNames.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: user.roleNames
                          .map((r) => _StatusChip(
                              label: r, color: AppColors.primary))
                          .toList(),
                    ),
                  ],
                ],
              ),
            ),

            // Last login
            if (user.lastLoginAt != null)
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Last login',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 11),
                    ),
                    Text(
                      _formatDate(user.lastLoginAt!),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),

            // Actions
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!user.isSuperAdmin) ...[
                  IconButton(
                    tooltip: 'Assign Roles',
                    icon: const Icon(Icons.manage_accounts_rounded, size: 18),
                    onPressed: () => _showRoleAssignDialog(context, ref),
                  ),
                  IconButton(
                    tooltip: user.isActive ? 'Deactivate' : 'Activate',
                    icon: Icon(
                      user.isActive
                          ? Icons.toggle_on_rounded
                          : Icons.toggle_off_rounded,
                      size: 22,
                      color: user.isActive
                          ? AppColors.success
                          : AppColors.textSecondary,
                    ),
                    onPressed: () => ref
                        .read(rbacAdminUsersNotifierProvider.notifier)
                        .updateAdminUser(user.id, isActive: !user.isActive),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showRoleAssignDialog(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (_) => _RoleAssignDialog(
        user: user,
        allRoles: allRoles,
        onSave: (roleIds) => ref
            .read(rbacAdminUsersNotifierProvider.notifier)
            .setAdminUserRoles(user.id, roleIds),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}/'
        '${dt.month.toString().padLeft(2, '0')}/'
        '${dt.year}';
  }
}

// ── Role assignment dialog ─────────────────────────────────────────────────────

class _RoleAssignDialog extends StatefulWidget {
  const _RoleAssignDialog({
    required this.user,
    required this.allRoles,
    required this.onSave,
  });
  final RbacAdminUser user;
  final List<Role> allRoles;
  final Future<void> Function(List<String> roleIds) onSave;

  @override
  State<_RoleAssignDialog> createState() => _RoleAssignDialogState();
}

class _RoleAssignDialogState extends State<_RoleAssignDialog> {
  late Set<String> _selectedRoleIds;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selectedRoleIds = Set.from(widget.user.roleIds);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.onSave(_selectedRoleIds.toList());
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Assign Roles — ${widget.user.displayName}'),
      content: SizedBox(
        width: 400,
        child: widget.allRoles.isEmpty
            ? const Text('No roles available.')
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: widget.allRoles
                    .where((r) => r.isActive)
                    .map(
                      (r) => CheckboxListTile(
                        dense: true,
                        title: Text(r.name),
                        subtitle: r.description != null
                            ? Text(r.description!,
                                style: const TextStyle(fontSize: 11))
                            : null,
                        value: _selectedRoleIds.contains(r.id),
                        onChanged: (v) {
                          setState(() {
                            if (v == true) {
                              _selectedRoleIds.add(r.id);
                            } else {
                              _selectedRoleIds.remove(r.id);
                            }
                          });
                        },
                      ),
                    )
                    .toList(),
              ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
