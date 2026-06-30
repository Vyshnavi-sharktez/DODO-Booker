import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../application/providers/dodo_teams_providers.dart';
import '../../domain/models/dodo_team.dart';
import '../widgets/dodo_team_form_dialog.dart';

const _statusConfig = <String, (String, Color, Color)>{
  'Available': ('Available', Color(0xFF38A169), Color(0xFFF0FFF4)),
  'Busy': ('Busy', Color(0xFFDD6B20), Color(0xFFFEEBC8)),
  'Inactive': ('Inactive', Color(0xFF718096), Color(0xFFF7FAFC)),
};

const _allStatuses = ['Available', 'Busy', 'Inactive'];

class DodoTeamsPage extends ConsumerStatefulWidget {
  const DodoTeamsPage({super.key});

  @override
  ConsumerState<DodoTeamsPage> createState() => _DodoTeamsPageState();
}

class _DodoTeamsPageState extends ConsumerState<DodoTeamsPage> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  String? _localityFilter;
  String? _statusFilter;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<DodoTeam> _applyFilters(List<DodoTeam> all) {
    var result = all;
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      result = result
          .where((t) =>
              t.teamName.toLowerCase().contains(q) ||
              (t.supervisorName?.toLowerCase().contains(q) ?? false) ||
              (t.locality?.toLowerCase().contains(q) ?? false))
          .toList();
    }
    if (_localityFilter != null) {
      result = result.where((t) => t.locality == _localityFilter).toList();
    }
    if (_statusFilter != null) {
      result = result.where((t) => t.status == _statusFilter).toList();
    }
    return result;
  }

  List<String> _uniqueLocalities(List<DodoTeam> teams) {
    return teams
        .map((t) => t.locality)
        .whereType<String>()
        .where((l) => l.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
  }

  void _openCreate() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => DodoTeamFormDialog(
        onSave: ({
          required teamName,
          supervisorName,
          phone,
          email,
          locality,
          required membersCount,
          required status,
        }) async {
          await ref.read(dodoTeamsNotifierProvider.notifier).createDodoTeam(
                teamName: teamName,
                supervisorName: supervisorName,
                phone: phone,
                email: email,
                locality: locality,
                membersCount: membersCount,
                status: status,
              );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Team created successfully')),
            );
          }
        },
      ),
    );
  }

  void _openEdit(DodoTeam team) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => DodoTeamFormDialog(
        existing: team,
        onSave: ({
          required teamName,
          supervisorName,
          phone,
          email,
          locality,
          required membersCount,
          required status,
        }) async {
          await ref.read(dodoTeamsNotifierProvider.notifier).updateDodoTeam(
                team.id,
                teamName: teamName,
                supervisorName: supervisorName,
                phone: phone,
                email: email,
                locality: locality,
                membersCount: membersCount,
                status: status,
              );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Team updated successfully')),
            );
          }
        },
      ),
    );
  }

  Future<void> _confirmDelete(DodoTeam team) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Delete Team'),
        content: Text(
          'Are you sure you want to delete "${team.teamName}"?\n\nThis action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref
          .read(dodoTeamsNotifierProvider.notifier)
          .deleteDodoTeam(team.id);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Team deleted')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Delete failed: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(dodoTeamsNotifierProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ───────────────────────────────────────────────────────
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 600;
              return Flex(
                direction: narrow ? Axis.vertical : Axis.horizontal,
                crossAxisAlignment: narrow
                    ? CrossAxisAlignment.start
                    : CrossAxisAlignment.center,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'DODO Teams',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Manage your internal service teams',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  if (narrow) const SizedBox(height: 12) else const Spacer(),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => ref
                            .read(dodoTeamsNotifierProvider.notifier)
                            .refresh(),
                        icon: const Icon(Icons.refresh_rounded, size: 16),
                        label: const Text('Refresh'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                        ),
                      ),
                      const SizedBox(width: 10),
                      FilledButton.icon(
                        onPressed: _openCreate,
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Add Team'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 12),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 20),

          // ── Dashboard stat cards ──────────────────────────────────────────
          state.when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (all) => _StatCards(teams: all),
          ),
          const SizedBox(height: 20),

          // ── Filters ──────────────────────────────────────────────────────
          state.when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (all) => Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 240,
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search team or supervisor…',
                      prefixIcon:
                          const Icon(Icons.search_rounded, size: 18),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                    ),
                    onChanged: (v) => setState(() => _searchQuery = v.trim()),
                  ),
                ),

                SizedBox(
                  width: 180,
                  child: DropdownButtonFormField<String>(
                    // ignore: deprecated_member_use
                    value: _localityFilter,
                    decoration: const InputDecoration(
                      hintText: 'Locality',
                      prefixIcon:
                          Icon(Icons.location_on_rounded, size: 18),
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                    ),
                    items: [
                      const DropdownMenuItem(
                          value: null, child: Text('All Localities')),
                      ..._uniqueLocalities(all).map(
                        (l) => DropdownMenuItem(value: l, child: Text(l)),
                      ),
                    ],
                    onChanged: (v) => setState(() => _localityFilter = v),
                    isExpanded: true,
                  ),
                ),

                SizedBox(
                  width: 160,
                  child: DropdownButtonFormField<String>(
                    // ignore: deprecated_member_use
                    value: _statusFilter,
                    decoration: const InputDecoration(
                      hintText: 'Status',
                      prefixIcon: Icon(Icons.flag_rounded, size: 18),
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                    ),
                    items: [
                      const DropdownMenuItem(
                          value: null, child: Text('All Statuses')),
                      ..._allStatuses.map(
                        (s) => DropdownMenuItem(
                          value: s,
                          child: Text(
                            _statusConfig[s]?.$1 ??
                                s[0].toUpperCase() + s.substring(1),
                          ),
                        ),
                      ),
                    ],
                    onChanged: (v) => setState(() => _statusFilter = v),
                    isExpanded: true,
                  ),
                ),

                if (_localityFilter != null ||
                    _statusFilter != null ||
                    _searchQuery.isNotEmpty)
                  TextButton.icon(
                    onPressed: () => setState(() {
                      _localityFilter = null;
                      _statusFilter = null;
                      _searchQuery = '';
                      _searchController.clear();
                    }),
                    icon: const Icon(Icons.filter_alt_off_rounded, size: 16),
                    label: const Text('Clear'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── Body ─────────────────────────────────────────────────────────
          Expanded(
            child: state.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline_rounded,
                        size: 48, color: AppColors.error),
                    const SizedBox(height: 12),
                    Text(
                      'Failed to load teams',
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      e.toString(),
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () => ref
                          .read(dodoTeamsNotifierProvider.notifier)
                          .refresh(),
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
              data: (all) {
                final filtered = _applyFilters(all);
                if (all.isEmpty) {
                  return _EmptyState(
                    message: 'No teams yet',
                    sub: 'Click "Add Team" to create the first one.',
                    onAdd: _openCreate,
                  );
                }
                if (filtered.isEmpty) {
                  return const _EmptyState(
                    message: 'No teams match your filters',
                    sub: 'Try adjusting your search or filters.',
                  );
                }
                return _TeamsTable(
                  teams: filtered,
                  totalCount: all.length,
                  onEdit: _openEdit,
                  onDelete: _confirmDelete,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Stat Cards ────────────────────────────────────────────────────────────────

class _StatCards extends StatelessWidget {
  final List<DodoTeam> teams;
  const _StatCards({required this.teams});

  @override
  Widget build(BuildContext context) {
    final total = teams.length;
    final active = teams.where((t) => t.status == 'Available').length;
    final busy = teams.where((t) => t.status == 'Busy').length;
    final available =
        teams.where((t) => t.status == 'Available' && t.activeJobs == 0).length;

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _StatCard(
          label: 'Total Teams',
          count: total,
          icon: Icons.groups_rounded,
          color: const Color(0xFF3182CE),
        ),
        _StatCard(
          label: 'Active',
          count: active,
          icon: Icons.check_circle_rounded,
          color: const Color(0xFF38A169),
        ),
        _StatCard(
          label: 'Busy',
          count: busy,
          icon: Icons.schedule_rounded,
          color: const Color(0xFFDD6B20),
        ),
        _StatCard(
          label: 'Available',
          count: available,
          icon: Icons.radio_button_checked_rounded,
          color: const Color(0xFF805AD5),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final int count;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.label,
    required this.count,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 160,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 8),
              Text(
                count.toString(),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Table ─────────────────────────────────────────────────────────────────────

class _TeamsTable extends StatelessWidget {
  final List<DodoTeam> teams;
  final int totalCount;
  final void Function(DodoTeam) onEdit;
  final void Function(DodoTeam) onDelete;

  const _TeamsTable({
    required this.teams,
    required this.totalCount,
    required this.onEdit,
    required this.onDelete,
  });

  static const double _minTableWidth = 860;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final tableWidth = constraints.maxWidth < _minTableWidth
                      ? _minTableWidth
                      : constraints.maxWidth;
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: tableWidth,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            color: AppColors.background,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            child: const Row(
                              children: [
                                _HeaderCell('Team Name', flex: 3),
                                _HeaderCell('Supervisor', flex: 2),
                                _HeaderCell('Members', flex: 1,
                                    align: TextAlign.center),
                                _HeaderCell('Locality', flex: 2),
                                _HeaderCell('Active Jobs', flex: 1,
                                    align: TextAlign.center),
                                _HeaderCell('Status', flex: 2),
                                _HeaderCell('Actions', flex: 2,
                                    align: TextAlign.center),
                              ],
                            ),
                          ),
                          const Divider(height: 1),
                          Expanded(
                            child: ListView.separated(
                              itemCount: teams.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemBuilder: (ctx, i) {
                                final t = teams[i];
                                return _TeamRow(
                                  team: t,
                                  onEdit: () => onEdit(t),
                                  onDelete: () => onDelete(t),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            Container(
              color: AppColors.background,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text(
                teams.length == totalCount
                    ? '${teams.length} team${teams.length == 1 ? '' : 's'}'
                    : '${teams.length} of $totalCount team${totalCount == 1 ? '' : 's'}',
                style: TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  final String label;
  final int flex;
  final TextAlign align;

  const _HeaderCell(this.label,
      {required this.flex, this.align = TextAlign.left});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Text(
        label,
        textAlign: align,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _TeamRow extends StatelessWidget {
  final DodoTeam team;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _TeamRow({
    required this.team,
    required this.onEdit,
    required this.onDelete,
  });

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: AppColors.primaryLight,
                  child: Text(
                    _initials(team.teamName),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    team.teamName,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            flex: 2,
            child: Text(
              team.supervisorName ?? '—',
              style: TextStyle(
                  fontSize: 13,
                  color: team.supervisorName != null
                      ? AppColors.textPrimary
                      : AppColors.textSecondary),
              overflow: TextOverflow.ellipsis,
            ),
          ),

          Expanded(
            flex: 1,
            child: Text(
              team.membersCount.toString(),
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary),
            ),
          ),

          Expanded(
            flex: 2,
            child: team.locality != null
                ? Row(
                    children: [
                      Icon(Icons.location_on_rounded,
                          size: 13, color: AppColors.textSecondary),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          team.locality!,
                          style: TextStyle(
                              fontSize: 13, color: AppColors.textPrimary),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  )
                : Text(
                    '—',
                    style: TextStyle(
                        fontSize: 13, color: AppColors.textSecondary),
                  ),
          ),

          Expanded(
            flex: 1,
            child: Text(
              team.activeJobs.toString(),
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: team.activeJobs > 0
                      ? const Color(0xFFDD6B20)
                      : AppColors.textSecondary),
            ),
          ),

          Expanded(
            flex: 2,
            child: _StatusBadge(status: team.status),
          ),

          Expanded(
            flex: 2,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: onEdit,
                  icon: Icon(Icons.edit_rounded,
                      size: 16, color: AppColors.accent),
                  tooltip: 'Edit',
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  onPressed: onDelete,
                  icon: Icon(Icons.delete_outline_rounded,
                      size: 16, color: AppColors.error),
                  tooltip: 'Delete',
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final cfg = _statusConfig[status];
    final label = cfg?.$1 ?? status;
    final color = cfg?.$2 ?? AppColors.textSecondary;
    final bg = cfg?.$3 ?? AppColors.background;

    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration:
                  BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String message;
  final String sub;
  final VoidCallback? onAdd;

  const _EmptyState({
    required this.message,
    required this.sub,
    this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.groups_outlined,
            size: 56,
            color: AppColors.textSecondary.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            sub,
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          if (onAdd != null) ...[
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('Add Team'),
              style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary),
            ),
          ],
        ],
      ),
    );
  }
}
