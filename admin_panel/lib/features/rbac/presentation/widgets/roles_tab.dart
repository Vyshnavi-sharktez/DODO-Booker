import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../features/auth/domain/models/admin_user.dart';
import '../../application/providers/rbac_providers.dart';
import '../../domain/models/permission.dart';
import '../../domain/models/role.dart';

// ── Module / operation definitions ────────────────────────────────────────────

class _PermOp {
  final String suffix;
  final String label;
  const _PermOp(this.suffix, this.label);
  String key(String prefix) => '$prefix.$suffix';
}

class _ModuleSpec {
  final String displayName;
  final String prefix;
  final List<_PermOp> ops;
  const _ModuleSpec(this.displayName, this.prefix, this.ops);
}

const _moduleSpecs = [
  _ModuleSpec('Bookings', 'booking', [
    _PermOp('create', 'Create'), _PermOp('read', 'Read'),
    _PermOp('update', 'Update'), _PermOp('delete', 'Delete'),
  ]),
  _ModuleSpec('Customers', 'customer', [
    _PermOp('create', 'Create'), _PermOp('read', 'Read'),
    _PermOp('update', 'Update'), _PermOp('delete', 'Delete'),
  ]),
  _ModuleSpec('Vendors', 'vendor', [
    _PermOp('create', 'Create'), _PermOp('read', 'Read'),
    _PermOp('update', 'Update'), _PermOp('delete', 'Delete'),
  ]),
  _ModuleSpec('Catalog', 'catalog', [
    _PermOp('create', 'Create'), _PermOp('read', 'Read'),
    _PermOp('update', 'Update'), _PermOp('delete', 'Delete'),
  ]),
  _ModuleSpec('Scheduling', 'scheduling', [
    _PermOp('create', 'Create'), _PermOp('read', 'Read'),
    _PermOp('update', 'Update'), _PermOp('delete', 'Delete'),
  ]),
  _ModuleSpec('Coupons', 'coupon', [
    _PermOp('create', 'Create'), _PermOp('read', 'Read'),
    _PermOp('update', 'Update'), _PermOp('delete', 'Delete'),
  ]),
  _ModuleSpec('Notifications', 'notification', [
    _PermOp('create', 'Create'), _PermOp('read', 'Read'),
  ]),
  _ModuleSpec('Settings', 'settings', [
    _PermOp('read', 'Read'), _PermOp('update', 'Update'),
  ]),
  _ModuleSpec('RBAC', 'rbac', [
    _PermOp('create', 'Create'), _PermOp('read', 'Read'),
    _PermOp('update', 'Update'), _PermOp('delete', 'Delete'),
  ]),
  _ModuleSpec('DODO Teams', 'dodo_team', [
    _PermOp('create', 'Create'), _PermOp('read', 'Read'),
    _PermOp('update', 'Update'), _PermOp('delete', 'Delete'),
  ]),
  _ModuleSpec('Support', 'support', [
    _PermOp('read', 'Read'), _PermOp('update', 'Update'),
  ]),
  _ModuleSpec('Refunds', 'refund', [
    _PermOp('view', 'View'),         _PermOp('review', 'Review'),
    _PermOp('approve', 'Approve'),   _PermOp('process', 'Process'),
    _PermOp('policy.manage', 'Policy'),
  ]),
];

// ── Expand legacy coarse permissions into CRUD equivalents ────────────────────

Set<String> _expandLegacyPerms(Set<String> raw, List<Permission> allPerms) {
  final nameToId = <String, String>{for (final p in allPerms) p.name: p.id};
  final idToName = <String, String>{for (final p in allPerms) p.id: p.name};
  final expanded = Set<String>.from(raw);
  for (final id in List<String>.from(raw)) {
    final permName = idToName[id];
    if (permName == null) continue;
    final implied = AdminUser.legacyImplied[permName];
    if (implied == null) continue;
    for (final impliedName in implied) {
      final impliedId = nameToId[impliedName];
      if (impliedId != null) expanded.add(impliedId);
    }
  }
  return expanded;
}

// ── Public tab widget ─────────────────────────────────────────────────────────

class RolesTab extends ConsumerWidget {
  const RolesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rolesAsync = ref.watch(rolesNotifierProvider);
    final permissionsAsync = ref.watch(permissionsProvider);

    return rolesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _ErrorView(
        message: e.toString(),
        onRetry: () => ref.read(rolesNotifierProvider.notifier).refresh(),
      ),
      data: (roles) => _RolesList(
        roles: roles,
        allPermissions: permissionsAsync.valueOrNull ?? [],
      ),
    );
  }
}

// ── Roles list ────────────────────────────────────────────────────────────────

class _RolesList extends ConsumerWidget {
  const _RolesList({required this.roles, required this.allPermissions});
  final List<Role> roles;
  final List<Permission> allPermissions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            children: [
              Text(
                'Roles',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: () => _showRoleDialog(context, ref, null),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('New Role'),
                style:
                    FilledButton.styleFrom(backgroundColor: AppColors.primary),
              ),
            ],
          ),
        ),
        Expanded(
          child: roles.isEmpty
              ? const Center(child: Text('No roles found.'))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  itemCount: roles.length,
                  separatorBuilder: (context, i) => const SizedBox(height: 8),
                  itemBuilder: (context, i) => _RoleCard(
                    role: roles[i],
                    allPermissions: allPermissions,
                  ),
                ),
        ),
      ],
    );
  }

  void _showRoleDialog(BuildContext context, WidgetRef ref, Role? existing) {
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

// ── Role card ─────────────────────────────────────────────────────────────────

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
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child:
                  Icon(Icons.shield_rounded, color: AppColors.primary, size: 22),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          role.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 14),
                          overflow: TextOverflow.ellipsis,
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
                    style:
                        TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
            Text(
              '${role.permissionCount} permission${role.permissionCount == 1 ? '' : 's'}',
              style:
                  TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(width: 16),
            if (!role.isSystem) ...[
              IconButton(
                tooltip: 'Edit',
                icon: const Icon(Icons.edit_rounded, size: 18),
                onPressed: () => _showEditDialog(context, ref),
              ),
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
                  size: 32,
                  color: role.isActive
                      ? AppColors.success
                      : AppColors.textSecondary,
                ),
                onPressed: () async {
                  try {
                    await ref
                        .read(rolesNotifierProvider.notifier)
                        .updateRole(role.id, isActive: !role.isActive);
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text('Failed to update role: $e'),
                        backgroundColor: AppColors.error,
                        behavior: SnackBarBehavior.floating,
                      ));
                    }
                  }
                },
              ),
            ],
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

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final count =
        await ref.read(rbacRepositoryProvider).fetchRoleAdminCount(role.id);
    if (!context.mounted) return;

    final detail = count > 0
        ? 'Delete "${role.name}"? $count admin${count == 1 ? '' : 's'} '
            'will lose this role. This cannot be undone.'
        : 'Delete "${role.name}"? This cannot be undone.';

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Role'),
        content: Text(detail),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () {
              Navigator.of(ctx).pop();
              ref.read(rolesNotifierProvider.notifier).deleteRole(role.id);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

// ── Role create / edit dialog ─────────────────────────────────────────────────

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
    // Expand any legacy coarse permissions to their CRUD equivalents so the
    // selector accurately reflects what the role currently grants.
    final raw = Set<String>.from(widget.existing?.permissionIds ?? []);
    _selectedPermIds = _expandLegacyPerms(raw, widget.allPermissions);
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
    final hasPerms = isEdit && widget.allPermissions.isNotEmpty;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 820,
          // Only cap height when showing permissions — new-role dialog stays compact
          maxHeight: hasPerms
              ? MediaQuery.of(context).size.height * 0.9
              : double.infinity,
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            // max-size when editing (fills ConstrainedBox so Expanded works);
            // min-size when creating (no Expanded, dialog is compact)
            mainAxisSize: hasPerms ? MainAxisSize.max : MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ────────────────────────────────────────────────────
              Row(
                children: [
                  Text(
                    isEdit ? 'Edit Role' : 'New Role',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // ── Name + description ────────────────────────────────────────
              Form(
                key: _formKey,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _name,
                        decoration:
                            const InputDecoration(labelText: 'Role Name *'),
                        validator: (v) =>
                            v == null || v.trim().isEmpty ? 'Required' : null,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextFormField(
                        controller: _desc,
                        decoration:
                            const InputDecoration(labelText: 'Description'),
                        maxLines: 1,
                      ),
                    ),
                  ],
                ),
              ),
              // ── Permission selector (edit only) ───────────────────────────
              if (hasPerms) ...[
                const SizedBox(height: 20),
                // Expanded fills remaining vertical space inside the Dialog
                Expanded(
                  child: _PermissionSelector(
                    allPermissions: widget.allPermissions,
                    selectedIds: _selectedPermIds,
                    onChanged: (ids) =>
                        setState(() => _selectedPermIds = ids),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              // ── Actions ───────────────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed:
                        _saving ? null : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary),
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
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Permission selector ───────────────────────────────────────────────────────
// Fills whatever height its parent Expanded gives it.
// Header row is fixed; module card grid scrolls in the remaining space.

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
    final nameToId = <String, String>{
      for (final p in allPermissions) p.name: p.id,
    };

    // All IDs present in the DB for the module specs
    final allModuleIds = <String>{};
    for (final spec in _moduleSpecs) {
      for (final op in spec.ops) {
        final id = nameToId[op.key(spec.prefix)];
        if (id != null) allModuleIds.add(id);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Section header + global controls ─────────────────────────────
        Row(
          children: [
            const Text(
              'Permissions',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const Spacer(),
            TextButton(
              onPressed: () =>
                  onChanged(Set<String>.from(selectedIds)..addAll(allModuleIds)),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: const Text('Select All', style: TextStyle(fontSize: 12)),
            ),
            TextButton(
              onPressed: () => onChanged(
                  Set<String>.from(selectedIds)..removeAll(allModuleIds)),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.error,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: const Text('Clear All', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // ── Scrollable module card grid ───────────────────────────────────
        // Expanded takes all space given by the parent Expanded in _RoleDialog.
        Expanded(
          child: SingleChildScrollView(
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _moduleSpecs
                  .map((spec) => _ModuleCard(
                        spec: spec,
                        nameToId: nameToId,
                        selectedIds: selectedIds,
                        onChanged: onChanged,
                      ))
                  .toList(),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Module card ───────────────────────────────────────────────────────────────

class _ModuleCard extends StatelessWidget {
  const _ModuleCard({
    required this.spec,
    required this.nameToId,
    required this.selectedIds,
    required this.onChanged,
  });
  final _ModuleSpec spec;
  final Map<String, String> nameToId;
  final Set<String> selectedIds;
  final ValueChanged<Set<String>> onChanged;

  List<String> get _existingIds => spec.ops
      .map((op) => nameToId[op.key(spec.prefix)])
      .whereType<String>()
      .toList();

  @override
  Widget build(BuildContext context) {
    final ids = _existingIds;
    if (ids.isEmpty) return const SizedBox.shrink();

    final selectedCount = ids.where(selectedIds.contains).length;
    final allSelected = selectedCount == ids.length;
    final someSelected = selectedCount > 0 && !allSelected;

    return Container(
      width: 238,
      decoration: BoxDecoration(
        border: Border.all(
          color: (someSelected || allSelected)
              ? AppColors.primary.withValues(alpha: 0.4)
              : AppColors.border,
        ),
        borderRadius: BorderRadius.circular(10),
        color: AppColors.surface,
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Card header: module name + tristate select-all checkbox
          Row(
            children: [
              Expanded(
                child: Text(
                  spec.displayName,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color:
                        allSelected ? AppColors.primary : AppColors.textPrimary,
                  ),
                ),
              ),
              SizedBox(
                width: 32,
                height: 32,
                child: Checkbox(
                  value: allSelected ? true : (someSelected ? null : false),
                  tristate: true,
                  activeColor: AppColors.primary,
                  onChanged: (_) {
                    final newIds = Set<String>.from(selectedIds);
                    if (allSelected) {
                      newIds.removeAll(ids);
                    } else {
                      newIds.addAll(ids);
                    }
                    onChanged(newIds);
                  },
                ),
              ),
            ],
          ),
          Divider(height: 10, color: AppColors.border),
          // CRUD checkboxes — two per row
          _buildOpsGrid(),
        ],
      ),
    );
  }

  Widget _buildOpsGrid() {
    final ops = spec.ops;
    final rows = <Widget>[];
    for (var i = 0; i < ops.length; i += 2) {
      rows.add(Row(
        children: [
          Expanded(child: _buildOpTile(ops[i])),
          if (i + 1 < ops.length)
            Expanded(child: _buildOpTile(ops[i + 1]))
          else
            const Expanded(child: SizedBox()),
        ],
      ));
      if (i + 2 < ops.length) rows.add(const SizedBox(height: 2));
    }
    return Column(mainAxisSize: MainAxisSize.min, children: rows);
  }

  Widget _buildOpTile(_PermOp op) {
    final id = nameToId[op.key(spec.prefix)];
    // Permission not yet in DB — show disabled placeholder
    if (id == null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: Checkbox(
              value: false,
              onChanged: null,
              activeColor: AppColors.primary,
            ),
          ),
          Text(
            op.label,
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary.withValues(alpha: 0.5),
            ),
          ),
        ],
      );
    }

    final checked = selectedIds.contains(id);
    return GestureDetector(
      onTap: () {
        final newIds = Set<String>.from(selectedIds);
        if (checked) {
          newIds.remove(id);
        } else {
          newIds.add(id);
        }
        onChanged(newIds);
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: Checkbox(
              value: checked,
              activeColor: AppColors.primary,
              onChanged: (v) {
                final newIds = Set<String>.from(selectedIds);
                if (v == true) {
                  newIds.add(id);
                } else {
                  newIds.remove(id);
                }
                onChanged(newIds);
              },
            ),
          ),
          Text(
            op.label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: checked ? FontWeight.w600 : FontWeight.normal,
              color: checked ? AppColors.primary : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shared helpers ────────────────────────────────────────────────────────────

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
