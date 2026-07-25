import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../application/providers/seo_providers.dart';
import '../../domain/models/seo_coverage_stats.dart';
import '../../domain/models/seo_global_settings.dart';

/// Compact SEO health banner shown above the tab content on the SEO Management
/// page. Displays live aggregate coverage data from the database.
///
/// Staleness rule:
///   isStale = lastGenerationAt is null
///          OR max(seoGlobal.updatedAt, stats.latestSeoUpdatedAt) > lastGenerationAt
///
/// [SeoGlobalSettings.updatedAt] is NOT bumped when the generator writes
/// [SeoGlobalSettings.lastGenerationAt], so the comparison is always accurate.
class SeoOverviewCard extends ConsumerWidget {
  const SeoOverviewCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final globalAsync = ref.watch(seoGlobalSettingsProvider);
    final statsAsync = ref.watch(seoCoverageStatsProvider);

    final global = globalAsync.valueOrNull;
    final stats = statsAsync.valueOrNull;
    final isLoading = globalAsync.isLoading || statsAsync.isLoading;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 10),
      child: isLoading
          ? const _LoadingRow()
          : _StatsRow(global: global, stats: stats),
    );
  }
}

// ── Stats row ─────────────────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.global, required this.stats});

  final SeoGlobalSettings? global;
  final SeoCoverageStats? stats;

  @override
  Widget build(BuildContext context) {
    // Capture as locals so Dart's flow analysis can promote nullability.
    final s = stats;
    final domainSet = global?.productionDomain?.trim().isNotEmpty == true;
    final lastGen = global?.lastGenerationAt;

    // Staleness: compare lastGenerationAt against the newest config update.
    final latestConfig = _latestOf(global?.updatedAt, s?.latestSeoUpdatedAt);
    final isStale = lastGen == null ||
        (latestConfig != null && latestConfig.isAfter(lastGen));

    return Row(
      children: [
        // Catalog SEO coverage
        Expanded(
          child: _StatCell(
            icon: Icons.grid_view_rounded,
            label: 'Catalog SEO',
            value: s == null
                ? '—'
                : '${s.configuredCatalogCount} / ${s.totalActiveCatalogNodes} nodes',
            subValue: s != null && s.unconfiguredCatalogCount > 0
                ? '${s.unconfiguredCatalogCount} need attention'
                : null,
            status: _catalogStatus(s),
          ),
        ),
        const _VerticalDivider(),
        // Location pages
        Expanded(
          child: _StatCell(
            icon: Icons.place_rounded,
            label: 'Location Pages',
            value: s == null
                ? '—'
                : s.configuredLocationCount == 0
                    ? 'Not configured'
                    : '${s.configuredLocationCount} page${s.configuredLocationCount == 1 ? '' : 's'}',
            subValue: s != null && s.configuredLocationCount > 0
                ? 'across ${s.totalActiveAreas} area${s.totalActiveAreas == 1 ? '' : 's'}'
                : null,
            status: s == null
                ? _CellStatus.neutral
                : s.configuredLocationCount > 0
                    ? _CellStatus.ok
                    : _CellStatus.neutral,
          ),
        ),
        const _VerticalDivider(),
        // Production domain
        Expanded(
          child: _StatCell(
            icon: Icons.language_rounded,
            label: 'Domain',
            value: domainSet
                ? _truncateDomain(global!.productionDomain!)
                : 'Not configured',
            status: domainSet ? _CellStatus.ok : _CellStatus.warn,
          ),
        ),
        const _VerticalDivider(),
        // Generation status / staleness
        Expanded(
          child: _StatCell(
            icon: isStale
                ? Icons.warning_amber_rounded
                : Icons.check_circle_rounded,
            label: 'Generation',
            value: lastGen == null
                ? 'Never generated'
                : isStale
                    ? 'May be stale'
                    : 'Generated ${_relativeTime(lastGen)}',
            subValue: isStale && lastGen != null
                ? 'Regenerate before deployment'
                : null,
            status: isStale ? _CellStatus.warn : _CellStatus.ok,
          ),
        ),
      ],
    );
  }

  _CellStatus _catalogStatus(SeoCoverageStats? stats) {
    if (stats == null) return _CellStatus.neutral;
    if (stats.configuredCatalogCount == 0) return _CellStatus.warn;
    if (stats.unconfiguredCatalogCount > 0) return _CellStatus.partial;
    return _CellStatus.ok;
  }

  DateTime? _latestOf(DateTime? a, DateTime? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a.isAfter(b) ? a : b;
  }

  String _truncateDomain(String domain) {
    final cleaned = domain.replaceFirst(RegExp(r'^https?://'), '');
    return cleaned.length > 22 ? '${cleaned.substring(0, 22)}…' : cleaned;
  }

  String _relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inDays > 30) return '${(diff.inDays / 30).floor()}mo ago';
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'just now';
  }
}

// ── Cell status enum ──────────────────────────────────────────────────────────

enum _CellStatus { ok, warn, partial, neutral }

extension _CellStatusX on _CellStatus {
  Color get color => switch (this) {
        _CellStatus.ok => AppColors.success,
        _CellStatus.warn => AppColors.warning,
        _CellStatus.partial => const Color(0xFFF6AD55),
        _CellStatus.neutral => AppColors.textSecondary,
      };
}

// ── Individual stat cell ──────────────────────────────────────────────────────

class _StatCell extends StatelessWidget {
  const _StatCell({
    required this.icon,
    required this.label,
    required this.value,
    required this.status,
    this.subValue,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? subValue;
  final _CellStatus status;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: status.color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Icon(icon, size: 15, color: status.color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                value,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: status == _CellStatus.neutral
                      ? AppColors.textSecondary
                      : AppColors.textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (subValue != null) ...[
                const SizedBox(height: 1),
                Text(
                  subValue!,
                  style: TextStyle(
                    fontSize: 10,
                    color: status.color,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ── Loading skeleton row ──────────────────────────────────────────────────────

class _LoadingRow extends StatelessWidget {
  const _LoadingRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(
        4,
        (i) => Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: i < 3 ? 16 : 0, left: i > 0 ? 16 : 0),
            child: Container(
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.border.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Vertical divider ──────────────────────────────────────────────────────────

class _VerticalDivider extends StatelessWidget {
  const _VerticalDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 40,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      color: AppColors.border,
    );
  }
}
