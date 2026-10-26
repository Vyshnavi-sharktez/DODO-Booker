import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../auth/application/providers/auth_provider.dart';
import '../../../vendors/application/providers/vendors_providers.dart';
import '../../../vendors/domain/models/vendor.dart';
import '../../../vendors/presentation/widgets/vendor_form_dialog.dart';
import '../../../vendors/presentation/widgets/vendor_location_picker_dialog.dart';
import '../../application/providers/rbac_providers.dart';
import '../../domain/models/rbac_admin_user.dart';
import '../../domain/models/role.dart';
import '../../domain/models/unified_user.dart';
import 'create_user_wizard.dart';

// ── Main tab ──────────────────────────────────────────────────────────────────

class AdminUsersTab extends ConsumerStatefulWidget {
  const AdminUsersTab({super.key});

  @override
  ConsumerState<AdminUsersTab> createState() => _AdminUsersTabState();
}

class _AdminUsersTabState extends ConsumerState<AdminUsersTab> {
  final _searchCtrl = TextEditingController();
  String _filter = 'all'; // 'all' | 'admins' | 'vendors'
  int _page = 0;
  static const _pageSize = 15;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<UnifiedUser> _buildList(
      List<RbacAdminUser> admins, List<Vendor> vendors) {
    final all = <UnifiedUser>[
      ...admins.map(UnifiedUser.fromAdmin),
      ...vendors.map(UnifiedUser.fromVendor),
    ];

    final q = _searchCtrl.text.trim().toLowerCase();
    final filtered = all.where((u) {
      if (_filter == 'admins' && u.type != UnifiedUserType.admin) return false;
      if (_filter == 'vendors' && u.type != UnifiedUserType.vendor) return false;
      if (q.isEmpty) return true;
      return u.displayName.toLowerCase().contains(q) ||
          u.email.toLowerCase().contains(q) ||
          u.phone.contains(q) ||
          u.id.toLowerCase().contains(q) ||
          (u.admin?.adminNumber?.toLowerCase().contains(q) ?? false);
    }).toList();

    // Sort: admins first, then vendors; alphabetical within groups
    filtered.sort((a, b) {
      final tCmp =
          a.type.index.compareTo(b.type.index);
      if (tCmp != 0) return tCmp;
      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });

    return filtered;
  }

  Future<void> _openCreateWizard() async {
    final created = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const CreateUserWizard(),
    );
    if (created == true) {
      ref.invalidate(rbacAdminUsersNotifierProvider);
      ref.invalidate(vendorsNotifierProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final adminsAsync = ref.watch(rbacAdminUsersNotifierProvider);
    final vendorsAsync = ref.watch(vendorsNotifierProvider);
    final rolesAsync = ref.watch(rolesProvider);

    final admins = adminsAsync.valueOrNull ?? [];
    final vendors = vendorsAsync.valueOrNull ?? [];
    final allRoles = rolesAsync.valueOrNull ?? [];

    final list = _buildList(admins, vendors);
    final totalPages = (list.length / _pageSize).ceil();
    final pageClamped = _page.clamp(0, totalPages == 0 ? 0 : totalPages - 1);
    final pageItems = list.skip(pageClamped * _pageSize).take(_pageSize).toList();

    final isLoading = adminsAsync.isLoading || vendorsAsync.isLoading;
    final hasError = adminsAsync.hasError || vendorsAsync.hasError;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header ──────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Users',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${list.length}',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Manage admin and vendor accounts',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 13),
                  ),
                ],
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: _openCreateWizard,
                icon: const Icon(Icons.person_add_rounded, size: 18),
                label: const Text('Create User'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 12),
                ),
              ),
            ],
          ),
        ),

        // ── Search + filter ──────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (_) => setState(() => _page = 0),
                    decoration: InputDecoration(
                      hintText: 'Search by name, email, phone, or ID…',
                      prefixIcon: const Icon(Icons.search_rounded, size: 18),
                      suffixIcon: _searchCtrl.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 16),
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() => _page = 0);
                              },
                            )
                          : null,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              _FilterChip(
                label: 'All',
                selected: _filter == 'all',
                onTap: () => setState(() {
                  _filter = 'all';
                  _page = 0;
                }),
              ),
              const SizedBox(width: 6),
              _FilterChip(
                label: 'Admins',
                selected: _filter == 'admins',
                onTap: () => setState(() {
                  _filter = 'admins';
                  _page = 0;
                }),
              ),
              const SizedBox(width: 6),
              _FilterChip(
                label: 'Vendors',
                selected: _filter == 'vendors',
                onTap: () => setState(() {
                  _filter = 'vendors';
                  _page = 0;
                }),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // ── Table ────────────────────────────────────────────────────────────
        Expanded(
          child: isLoading
              ? const Center(child: CircularProgressIndicator())
              : hasError
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.error_outline_rounded,
                              color: AppColors.error, size: 36),
                          const SizedBox(height: 8),
                          const Text('Failed to load users.'),
                          const SizedBox(height: 12),
                          OutlinedButton(
                            onPressed: () {
                              ref.invalidate(
                                  rbacAdminUsersNotifierProvider);
                              ref.invalidate(vendorsNotifierProvider);
                            },
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    )
                  : Column(
                      children: [
                        _TableHeader(),
                        Expanded(
                          child: pageItems.isEmpty
                              ? Center(
                                  child: Text(
                                    'No users found.',
                                    style: TextStyle(
                                        color: AppColors.textSecondary),
                                  ),
                                )
                              : ListView.separated(
                                  padding: const EdgeInsets.fromLTRB(
                                      24, 0, 24, 8),
                                  itemCount: pageItems.length,
                                  separatorBuilder: (_, _) =>
                                      const SizedBox(height: 4),
                                  itemBuilder: (ctx, i) => _UserRow(
                                    user: pageItems[i],
                                    allRoles: allRoles,
                                  ),
                                ),
                        ),
                        if (totalPages > 1)
                          _Pagination(
                            page: pageClamped,
                            totalPages: totalPages,
                            total: list.length,
                            pageSize: _pageSize,
                            onPrev: pageClamped > 0
                                ? () =>
                                    setState(() => _page = pageClamped - 1)
                                : null,
                            onNext: pageClamped < totalPages - 1
                                ? () =>
                                    setState(() => _page = pageClamped + 1)
                                : null,
                          ),
                      ],
                    ),
        ),
      ],
    );
  }
}

// ── Table header row ──────────────────────────────────────────────────────────

class _TableHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      color: AppColors.textSecondary,
      letterSpacing: 0.4,
    );
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border),
      ),
      child: const Row(
        children: [
          Expanded(flex: 3, child: Text('NAME', style: style)),
          SizedBox(
              width: 90,
              child: Text('TYPE', style: style)),
          SizedBox(
              width: 130,
              child: Text('PHONE', style: style)),
          Expanded(
              flex: 3,
              child: Text('EMAIL', style: style)),
          SizedBox(
              width: 80,
              child: Text('STATUS', style: style)),
          SizedBox(
              width: 96,
              child: Text('JOINED', style: style)),
          SizedBox(
              width: 140,
              child: Text('ACTIONS', style: style,
                  textAlign: TextAlign.right)),
        ],
      ),
    );
  }
}

// ── User row ──────────────────────────────────────────────────────────────────

class _UserRow extends ConsumerWidget {
  const _UserRow({required this.user, required this.allRoles});
  final UnifiedUser user;
  final List<Role> allRoles;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = user.type == UnifiedUserType.admin;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          // Name + avatar
          Expanded(
            flex: 3,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: (isAdmin ? AppColors.primary : AppColors.accent)
                      .withValues(alpha: 0.12),
                  child: Text(
                    user.displayName.isNotEmpty
                        ? user.displayName[0].toUpperCase()
                        : '?',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isAdmin ? AppColors.primary : AppColors.accent,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        user.displayName,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (isAdmin && user.admin?.adminNumber != null) ...[
                        const SizedBox(height: 2),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                                color: AppColors.primary.withValues(alpha: 0.3),
                                width: 1),
                          ),
                          child: Text(
                            user.admin!.adminNumber!,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Type badge
          SizedBox(
            width: 90,
            child: _Badge(
              label: isAdmin ? 'Admin' : 'Vendor',
              color: isAdmin ? AppColors.primary : AppColors.accent,
            ),
          ),

          // Phone
          SizedBox(
            width: 130,
            child: Text(
              user.phone.isNotEmpty ? user.phone : '—',
              style: TextStyle(
                  fontSize: 12, color: AppColors.textSecondary),
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // Email
          Expanded(
            flex: 3,
            child: Text(
              user.email,
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // Status
          SizedBox(
            width: 80,
            child: _Badge(
              label: user.isActive ? 'Active' : 'Inactive',
              color: user.isActive ? AppColors.success : AppColors.error,
            ),
          ),

          // Joined
          SizedBox(
            width: 96,
            child: Text(
              user.joinedAt != null ? _formatDate(user.joinedAt!) : '—',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ),

          // Actions
          SizedBox(
            width: 140,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (isAdmin && user.admin != null) ...[
                  _ActionBtn(
                    tooltip: 'Edit',
                    icon: Icons.edit_rounded,
                    onTap: () => _editAdmin(context, ref, user.admin!),
                  ),
                  if (!user.admin!.isSuperAdmin) ...[
                    _ActionBtn(
                      tooltip: 'Assign Roles',
                      icon: Icons.manage_accounts_rounded,
                      onTap: () => _showRoleDialog(context, ref, user.admin!),
                    ),
                    _ActionBtn(
                      tooltip: user.isActive ? 'Deactivate' : 'Activate',
                      icon: user.isActive
                          ? Icons.toggle_on_rounded
                          : Icons.toggle_off_rounded,
                      color: user.isActive
                          ? AppColors.success
                          : AppColors.textSecondary,
                      onTap: () => _toggleAdmin(context, ref, user.admin!),
                    ),
                    _ActionBtn(
                      tooltip: 'Delete',
                      icon: Icons.delete_rounded,
                      color: AppColors.error,
                      onTap: () => _deleteAdmin(context, ref, user.admin!),
                    ),
                  ],
                ],
                if (!isAdmin && user.vendor != null) ...[
                  _ActionBtn(
                    tooltip: 'Edit Vendor',
                    icon: Icons.edit_rounded,
                    onTap: () => _editVendor(context, ref, user.vendor!),
                  ),
                  _ActionBtn(
                    tooltip: user.isActive ? 'Deactivate' : 'Activate',
                    icon: user.isActive
                        ? Icons.toggle_on_rounded
                        : Icons.toggle_off_rounded,
                    color: user.isActive
                        ? AppColors.success
                        : AppColors.textSecondary,
                    onTap: () => _toggleVendor(context, ref, user.vendor!),
                  ),
                  _ActionBtn(
                    tooltip: 'Delete',
                    icon: Icons.delete_rounded,
                    color: AppColors.error,
                    onTap: () => _deleteVendor(context, ref, user.vendor!),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _editAdmin(
      BuildContext context, WidgetRef ref, RbacAdminUser admin) {
    showDialog<void>(
      context: context,
      builder: (_) => _AdminEditDialog(admin: admin),
    );
  }

  Future<void> _deleteAdmin(
      BuildContext context, WidgetRef ref, RbacAdminUser admin) async {
    final me = ref.read(currentAdminUserProvider);
    if (me?.id == admin.id) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You cannot delete your own account.'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _DeleteConfirmDialog(
        name: admin.displayName,
        subtitle: 'This will remove the admin account and all role assignments. '
            'Bookings, vendor profiles, and business data are not affected.',
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref
          .read(rbacAdminUsersNotifierProvider.notifier)
          .deleteAdminUser(admin.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Admin deleted.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _deleteVendor(
      BuildContext context, WidgetRef ref, Vendor vendor) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _DeleteConfirmDialog(
        name: vendor.businessName,
        subtitle: 'This will remove the vendor account from the system.',
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref
          .read(vendorsNotifierProvider.notifier)
          .deleteVendor(vendor.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Vendor deleted.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _showRoleDialog(
      BuildContext context, WidgetRef ref, RbacAdminUser admin) {
    showDialog<void>(
      context: context,
      builder: (_) => _RoleAssignDialog(
        user: admin,
        allRoles: allRoles,
        onSave: (roleIds) => ref
            .read(rbacAdminUsersNotifierProvider.notifier)
            .setAdminUserRoles(admin.id, roleIds),
      ),
    );
  }

  Future<void> _toggleAdmin(
      BuildContext context, WidgetRef ref, RbacAdminUser admin) async {
    if (admin.isActive) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: const Text('Deactivate Admin User'),
          content: Text(
            'Are you sure you want to deactivate "${admin.fullName}"?\n\n'
            'They will lose access to the admin panel immediately.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style:
                  FilledButton.styleFrom(backgroundColor: AppColors.error),
              child: const Text('Deactivate'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    try {
      await ref
          .read(rbacAdminUsersNotifierProvider.notifier)
          .updateAdminUser(admin.id, isActive: !admin.isActive);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _editVendor(BuildContext context, WidgetRef ref, Vendor vendor) {
    showDialog<void>(
      context: context,
      builder: (_) => VendorFormDialog(
        existing: vendor,
        onSave: ({
          required String businessName,
          String? ownerName,
          required String phone,
          required String email,
          required String city,
          String? address,
          required String status,
          required bool isActive,
          double? rating,
          double? latitude,
          double? longitude,
          double? commissionRate,
          required bool isPreferredVendor,
          required double preferredVendorFee,
        }) =>
            ref.read(vendorsNotifierProvider.notifier).updateVendor(
                  vendor.id,
                  businessName: businessName,
                  ownerName: ownerName,
                  phone: phone,
                  email: email,
                  city: city,
                  address: address,
                  status: status,
                  isActive: isActive,
                  rating: rating,
                  latitude: latitude,
                  longitude: longitude,
                  commissionRate: commissionRate,
                  isPreferredVendor: isPreferredVendor,
                  preferredVendorFee: preferredVendorFee,
                ),
      ),
    );
  }

  Future<void> _toggleVendor(
      BuildContext context, WidgetRef ref, Vendor vendor) async {
    if (vendor.isActive) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: const Text('Deactivate Vendor'),
          content: Text(
            'Are you sure you want to deactivate "${vendor.businessName}"?\n\n'
            'They will no longer be able to receive or accept bookings.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style:
                  FilledButton.styleFrom(backgroundColor: AppColors.error),
              child: const Text('Deactivate'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    try {
      await ref
          .read(vendorsNotifierProvider.notifier)
          .toggleActive(vendor.id, currentIsActive: vendor.isActive);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  String _formatDate(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}/'
        '${dt.month.toString().padLeft(2, '0')}/'
        '${dt.year}';
  }
}

// ── Role assignment dialog (reused from old tab) ───────────────────────────────

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
          style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary),
          child: _saving
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}

// ── Admin edit dialog ─────────────────────────────────────────────────────────

class _AdminEditDialog extends ConsumerStatefulWidget {
  const _AdminEditDialog({required this.admin});
  final RbacAdminUser admin;

  @override
  ConsumerState<_AdminEditDialog> createState() => _AdminEditDialogState();
}

class _AdminEditDialogState extends ConsumerState<_AdminEditDialog> {
  late final TextEditingController _emailCtrl;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _addressCtrl;
  double? _latitude;
  double? _longitude;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _emailCtrl = TextEditingController(text: widget.admin.email);
    _nameCtrl = TextEditingController(text: widget.admin.fullName);
    _phoneCtrl = TextEditingController(text: widget.admin.phone ?? '');
    _addressCtrl = TextEditingController(text: widget.admin.address ?? '');
    _latitude = widget.admin.latitude;
    _longitude = widget.admin.longitude;
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickOnMap() async {
    final result = await showDialog<VendorLocationPickerResult>(
      context: context,
      builder: (_) => VendorLocationPickerDialog(
        initialLatitude: _latitude,
        initialLongitude: _longitude,
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _latitude = result.latitude;
      _longitude = result.longitude;
      if (result.address?.isNotEmpty == true) _addressCtrl.text = result.address!;
    });
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Full name is required.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final phone = _phoneCtrl.text.trim();
      final address = _addressCtrl.text.trim();
      await ref.read(rbacAdminUsersNotifierProvider.notifier).updateAdminUser(
            widget.admin.id,
            fullName: name,
            phone: phone.isNotEmpty ? phone : null,
            address: address,
            latitude: address.isNotEmpty ? _latitude : null,
            longitude: address.isNotEmpty ? _longitude : null,
          );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Edit — ${widget.admin.displayName}'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Admin ID — read-only sequential ID
            if (widget.admin.adminNumber != null) ...[
              Row(
                children: [
                  Icon(Icons.tag_rounded,
                      size: 14, color: AppColors.textSecondary),
                  const SizedBox(width: 6),
                  Text(
                    'Admin ID: ',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.3),
                          width: 1),
                    ),
                    child: Text(
                      widget.admin.adminNumber!,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            // Email — read-only auth identity
            TextField(
              controller: _emailCtrl,
              readOnly: true,
              decoration: InputDecoration(
                labelText: 'Email',
                prefixIcon: const Icon(Icons.email_rounded),
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: AppColors.background,
                suffixIcon: Tooltip(
                  message: 'Email cannot be changed after account creation',
                  child: Icon(
                    Icons.lock_outline_rounded,
                    size: 18,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Full Name *',
                prefixIcon: Icon(Icons.person_rounded),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone',
                prefixIcon: Icon(Icons.phone_rounded),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            // Address with map picker
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _addressCtrl,
                    maxLines: 2,
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: (_) {
                      if (_addressCtrl.text.trim().isEmpty) {
                        setState(() {
                          _latitude = null;
                          _longitude = null;
                        });
                      }
                    },
                    decoration: InputDecoration(
                      labelText: 'Address',
                      prefixIcon: const Icon(Icons.location_pin),
                      border: const OutlineInputBorder(
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(8),
                          bottomLeft: Radius.circular(8),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(8),
                          bottomLeft: Radius.circular(8),
                        ),
                        borderSide: BorderSide(color: AppColors.border),
                      ),
                      focusedBorder: const OutlineInputBorder(
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(8),
                          bottomLeft: Radius.circular(8),
                        ),
                        borderSide:
                            BorderSide(color: AppColors.primary, width: 2),
                      ),
                    ),
                  ),
                ),
                InkWell(
                  onTap: _saving ? null : _pickOnMap,
                  child: Container(
                    height: 56,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: const BorderRadius.only(
                        topRight: Radius.circular(8),
                        bottomRight: Radius.circular(8),
                      ),
                      border: Border.all(color: AppColors.primary),
                    ),
                    child: const Icon(Icons.map_rounded,
                        color: Colors.white, size: 20),
                  ),
                ),
              ],
            ),
            if (_latitude != null && _longitude != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    Icon(Icons.location_on_rounded,
                        size: 13, color: AppColors.success),
                    const SizedBox(width: 4),
                    Text(
                      '${_latitude!.toStringAsFixed(5)}, '
                      '${_longitude!.toStringAsFixed(5)}',
                      style: TextStyle(
                          fontSize: 11, color: AppColors.success),
                    ),
                  ],
                ),
              ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!,
                  style: TextStyle(color: AppColors.error, fontSize: 12)),
            ],
          ],
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
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}

// ── Delete confirmation dialog ────────────────────────────────────────────────

class _DeleteConfirmDialog extends StatelessWidget {
  const _DeleteConfirmDialog({required this.name, required this.subtitle});
  final String name;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Confirm Delete'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RichText(
              text: TextSpan(
                style: DefaultTextStyle.of(context).style,
                children: [
                  const TextSpan(text: 'Delete '),
                  TextSpan(
                    text: name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const TextSpan(text: '?'),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(subtitle,
                style: TextStyle(
                    fontSize: 12, color: AppColors.textSecondary)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: FilledButton.styleFrom(backgroundColor: AppColors.error),
          child: const Text('Delete'),
        ),
      ],
    );
  }
}

// ── Small widgets ─────────────────────────────────────────────────────────────

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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

class _ActionBtn extends StatelessWidget {
  const _ActionBtn({
    required this.tooltip,
    required this.icon,
    required this.onTap,
    this.color,
  });
  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            icon,
            size: 20,
            color: color ?? AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary
              : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _Pagination extends StatelessWidget {
  const _Pagination({
    required this.page,
    required this.totalPages,
    required this.total,
    required this.pageSize,
    required this.onPrev,
    required this.onNext,
  });
  final int page;
  final int totalPages;
  final int total;
  final int pageSize;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final start = page * pageSize + 1;
    final end = ((page + 1) * pageSize).clamp(0, total);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
      child: Row(
        children: [
          Text(
            'Showing $start–$end of $total',
            style: TextStyle(
                fontSize: 12, color: AppColors.textSecondary),
          ),
          const Spacer(),
          OutlinedButton.icon(
            onPressed: onPrev,
            icon: const Icon(Icons.chevron_left_rounded, size: 18),
            label: const Text('Prev'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 8),
              textStyle: const TextStyle(fontSize: 13),
            ),
          ),
          const SizedBox(width: 8),
          Text('${page + 1} / $totalPages',
              style: const TextStyle(fontSize: 13)),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right_rounded, size: 18),
            label: const Text('Next'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 8),
              textStyle: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
