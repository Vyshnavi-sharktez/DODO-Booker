import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../application/providers/rbac_providers.dart';
import '../../domain/models/permission.dart';
import '../../domain/models/role.dart';

class RolesTab extends ConsumerWidget {
  const RolesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rolesAsync = ref.watch(rolesNotifierProvider);
    final permissionsAsync = ref.watch(permissionsProvider);

    return rolesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _ErrorView(message: e.toString(), onRetry: () {
        ref.read(rolesNotifierProvider.notifier).refresh();
      }),
      data: (roles) => _RolesList(
        roles: roles,
        allPermissions: permissionsAsync.valueOrNull ?? [],
      ),
    );
  }
}

class _RolesList extends ConsumerWidget {
  const _RolesList({required this.roles, required this.allPermissions});
  final List<Role> roles;
  final List<Permission> allPermissions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header row
        Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            children: [
              Text(
                'Roles',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: () => _showRoleDialog(context, ref, null),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('New Role'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                ),
              ),
            ],
          ),
        ),

        // Table
        Expanded(
          child: roles.isEmpty
              ? const Center(child: Text('No roles found.'))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  itemCount: roles.length,
                  separatorBuilder: (_, i) => const SizedBox(height: 8),
                  itemBuilder: (context, i) => _RoleCard(
                    role: roles[i],
                    allPermissions: allPermissions,
                  ),
                ),
        ),
      ],
    );
  }

  void _showRoleDialog(
    BuildContext context,
    WidgetRef ref,
    Role? existing,
  ) {
    showDialog<void>(
      context: context,
      builder: (_) => _RoleDialog(
        existing: existing,
        allPermissions: allPermissions,
        onSave: (name, description, permIds) async {
          final notifier = ref.read(rolesNotifierProvider.notifier);
          if (existing == null) {
            await notifier.createRole(name: name, description: description);
          } else {
            await notifier.updateRole(existing.id,
                name: name, description: description);
            if (permIds != null) {
              await notifier.setRolePermissions(existing.id, permIds);
            }
          }
        },
      ),
    );
  }
}

class _RoleCard extends ConsumerWidget {
  const _RoleCard({required this.role, required this.allPermissions});
  final Role role;
  final List<Permission> allPermissions;

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
            // Role icon
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.shield_rounded,
                color: AppColors.primary,
                size: 22,
              ),
            ),
            const SizedBox(width: 16),

            // Name + meta
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        role.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (role.isSystem)
                        _Chip(label: 'System', color: AppColors.accent),
                      if (!role.isActive)
                        _Chip(label: 'Inactive', color: AppColors.error),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    role.description ?? '',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),

            // Permission count
            Text(
              '${role.permissionCount} permission${role.permissionCount == 1 ? '' : 's'}',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(width: 16),

            // Actions
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Edit',
                  icon: const Icon(Icons.edit_rounded, size: 18),
                  onPressed: () => _showEditDialog(context, ref),
                ),
                if (!role.isSystem)
                  IconButton(
                    tooltip: 'Delete',
                    icon: Icon(Icons.delete_outline_rounded,
                        size: 18, color: AppColors.error),
                    onPressed: () => _confirmDelete(context, ref),
                  ),
                IconButton(
                  tooltip: role.isActive ? 'Deactivate' : 'Activate',
                  icon: Icon(
                    role.isActive
                        ? Icons.toggle_on_rounded
                        : Icons.toggle_off_rounded,
                    size: 22,
                    color: role.isActive ? AppColors.success : AppColors.textSecondary,
                  ),
                  onPressed: role.isSystem
                      ? null
                      : () => ref
                          .read(rolesNotifierProvider.notifier)
                          .updateRole(role.id, isActive: !role.isActive),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showEditDialog(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (_) => _RoleDialog(
        existing: role,
        allPermissions: allPermissions,
        onSave: (name, description, permIds) async {
          final notifier = ref.read(rolesNotifierProvider.notifier);
          await notifier.updateRole(role.id,
              name: name, description: description);
          if (permIds != null) {
            await notifier.setRolePermissions(role.id, permIds);
          }
        },
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Role'),
        content: Text('Delete "${role.name}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () {
              Navigator.of(context).pop();
              ref.read(rolesNotifierProvider.notifier).deleteRole(role.id);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

// ── Role create / edit dialog ──────────────────────────────────────────────────

class _RoleDialog extends StatefulWidget {
  const _RoleDialog({
    this.existing,
    required this.allPermissions,
    required this.onSave,
  });
  final Role? existing;
  final List<Permission> allPermissions;
  final Future<void> Function(
          String name, String? description, List<String>? permIds)
      onSave;

  @override
  State<_RoleDialog> createState() => _RoleDialogState();
}

class _RoleDialogState extends State<_RoleDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _desc;
  late Set<String> _selectedPermIds;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.existing?.name ?? '');
    _desc = TextEditingController(text: widget.existing?.description ?? '');
    _selectedPermIds = Set.from(widget.existing?.permissionIds ?? []);
  }

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await widget.onSave(
        _name.text.trim(),
        _desc.text.trim().isEmpty ? null : _desc.text.trim(),
        widget.existing != null ? _selectedPermIds.toList() : null,
      );
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
    final isEdit = widget.existing != null;
    return AlertDialog(
      title: Text(isEdit ? 'Edit Role' : 'New Role'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Role Name *'),
                  validator: (v) =>
                      v == null || v.isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _desc,
                  decoration:
                      const InputDecoration(labelText: 'Description'),
                  maxLines: 2,
                ),
                if (isEdit && widget.allPermissions.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  const Text(
                    'Permissions',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  _PermissionSelector(
                    allPermissions: widget.allPermissions,
                    selectedIds: _selectedPermIds,
                    onChanged: (ids) =>
                        setState(() => _selectedPermIds = ids),
                  ),
                ],
              ],
            ),
          ),
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

class _PermissionSelector extends StatelessWidget {
  const _PermissionSelector({
    required this.allPermissions,
    required this.selectedIds,
    required this.onChanged,
  });
  final List<Permission> allPermissions;
  final Set<String> selectedIds;
  final ValueChanged<Set<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    // Group by module
    final byModule = <String, List<Permission>>{};
    for (final p in allPermissions) {
      byModule.putIfAbsent(p.module, () => []).add(p);
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      constraints: const BoxConstraints(maxHeight: 300),
      child: ListView(
        shrinkWrap: true,
        children: byModule.entries.map((entry) {
          final modulePerms = entry.value;
          final allSelected =
              modulePerms.every((p) => selectedIds.contains(p.id));
          return ExpansionTile(
            title: Row(
              children: [
                Text(
                  entry.key,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                Checkbox(
                  value: allSelected,
                  tristate: modulePerms
                          .any((p) => selectedIds.contains(p.id)) &&
                      !allSelected,
                  onChanged: (_) {
                    final newIds = Set<String>.from(selectedIds);
                    if (allSelected) {
                      newIds.removeAll(modulePerms.map((p) => p.id));
                    } else {
                      newIds.addAll(modulePerms.map((p) => p.id));
                    }
                    onChanged(newIds);
                  },
                ),
              ],
            ),
            children: modulePerms
                .map((p) => CheckboxListTile(
                      dense: true,
                      title: Text(p.name,
                          style: const TextStyle(fontSize: 13)),
                      subtitle: p.description != null
                          ? Text(p.description!,
                              style: const TextStyle(fontSize: 11))
                          : null,
                      value: selectedIds.contains(p.id),
                      onChanged: (v) {
                        final newIds = Set<String>.from(selectedIds);
                        if (v == true) {
                          newIds.add(p.id);
                        } else {
                          newIds.remove(p.id);
                        }
                        onChanged(newIds);
                      },
                    ))
                .toList(),
          );
        }).toList(),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
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

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline_rounded, color: AppColors.error, size: 40),
          const SizedBox(height: 12),
          Text(message,
              style: TextStyle(color: AppColors.textSecondary),
              textAlign: TextAlign.center),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
