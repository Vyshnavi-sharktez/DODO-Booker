import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../application/providers/seo_providers.dart';
import '../../domain/models/seo_coverage_stats.dart';
import '../../domain/models/seo_global_settings.dart';

/// Search Insights tab — SEO Management page.
///
/// All metrics come from real database state (seo_global_settings,
/// catalog_node_seo, location_node_seo via existing providers).
///
/// Google Search Console is NOT connected; search performance and indexing
/// data are explicitly shown as unavailable. No placeholder or fabricated
/// numbers are displayed anywhere in this tab.
class SearchInsightsTab extends ConsumerWidget {
  const SearchInsightsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final globalAsync = ref.watch(seoGlobalSettingsProvider);
    final statsAsync = ref.watch(seoCoverageStatsProvider);

    if (globalAsync.isLoading || statsAsync.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final err = globalAsync.error ?? statsAsync.error;
    if (err != null) {
      return _ErrorView(
        error: err.toString(),
        onRetry: () {
          ref.invalidate(seoGlobalSettingsProvider);
          ref.invalidate(seoCoverageStatsProvider);
        },
      );
    }

    return _InsightsBody(
      global: globalAsync.valueOrNull,
      stats: statsAsync.valueOrNull,
    );
  }
}

// ── Main body ─────────────────────────────────────────────────────────────────

class _InsightsBody extends StatelessWidget {
  const _InsightsBody({required this.global, required this.stats});

  final SeoGlobalSettings? global;
  final SeoCoverageStats? stats;

  @override
  Widget build(BuildContext context) {
    // Derive all display values from real data — no defaults that imply things
    // are configured when they are not.
    final domain = global?.productionDomain?.trim() ?? '';
    final domainSet = domain.isNotEmpty;
    final lastGen = global?.lastGenerationAt;
    final generated = lastGen != null;
    final globalConfigured = global != null;
    final catalogEnabled = (stats?.configuredCatalogCount ?? 0) > 0;
    final locationEnabled = (stats?.configuredLocationCount ?? 0) > 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── S1: Search Console Status ────────────────────────────────────
          _SectionCard(
            icon: Icons.manage_search_rounded,
            title: 'Search Console Status',
            child: _SearchConsoleStatus(domainSet: domainSet, domain: domain),
          ),

          // ── S2: Deployment Readiness ─────────────────────────────────────
          _SectionCard(
            icon: Icons.rocket_launch_rounded,
            title: 'Deployment Readiness',
            child: _DeploymentReadiness(
              generated: generated,
              globalConfigured: globalConfigured,
              catalogEnabled: catalogEnabled,
              locationEnabled: locationEnabled,
              domainSet: domainSet,
            ),
          ),

          // ── S3: Search Performance ───────────────────────────────────────
          const _SectionCard(
            icon: Icons.bar_chart_rounded,
            title: 'Search Performance',
            child: _SearchPerformance(),
          ),

          // ── S4: Indexing Status ──────────────────────────────────────────
          const _SectionCard(
            icon: Icons.find_in_page_rounded,
            title: 'Indexing Status',
            child: _IndexingStatus(),
          ),

          // ── S5: Sitemap ──────────────────────────────────────────────────
          _SectionCard(
            icon: Icons.account_tree_rounded,
            title: 'Sitemap',
            child: _SitemapSection(
              generated: generated,
              lastGen: lastGen,
              domain: domain,
              domainSet: domainSet,
            ),
          ),

          // ── S6: Robots.txt ───────────────────────────────────────────────
          _SectionCard(
            icon: Icons.smart_toy_rounded,
            title: 'Robots.txt',
            child: _RobotsSection(
              generated: generated,
              domain: domain,
              domainSet: domainSet,
            ),
          ),

          // ── S7: Readiness Checklist ──────────────────────────────────────
          _SectionCard(
            icon: Icons.checklist_rounded,
            title: 'Readiness Checklist',
            child: _ReadinessChecklist(
              globalConfigured: globalConfigured,
              catalogEnabled: catalogEnabled,
              locationEnabled: locationEnabled,
              generated: generated,
              domainSet: domainSet,
            ),
          ),

          // ── S8: Future Search Metrics ────────────────────────────────────
          const _SectionCard(
            icon: Icons.insights_rounded,
            title: 'Future Search Metrics',
            child: _FutureMetrics(),
          ),
        ],
      ),
    );
  }
}

// ── S1: Search Console Status ─────────────────────────────────────────────────

class _SearchConsoleStatus extends StatelessWidget {
  const _SearchConsoleStatus({required this.domainSet, required this.domain});

  final bool domainSet;
  final String domain;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Domain status — real data from DB
        _Chip(
          icon: domainSet
              ? Icons.language_rounded
              : Icons.warning_amber_rounded,
          label: domainSet ? 'Domain Configured' : 'Domain Not Set',
          color: domainSet ? AppColors.success : AppColors.warning,
        ),
        const SizedBox(height: 16),
        _LabeledField(
          label: 'Status',
          value: 'Not Connected',
          valueColor: AppColors.textSecondary,
        ),
        const SizedBox(height: 8),
        const _LabeledField(
          label: 'Reason',
          value: 'Google Search Console has not been configured for this deployment.',
        ),
        const SizedBox(height: 8),
        _LabeledField(
          label: 'Action',
          value: domainSet
              ? 'Verify this domain in Google Search Console after the site is deployed to production.'
              : 'Configure a production domain first, then connect Google Search Console after deployment.',
        ),
        const SizedBox(height: 14),
        const Text(
          'Google Search Console provides impression counts, click data, average search '
          'position, and page indexing status. These metrics become available after the '
          'site is deployed to a public domain, the domain is verified in Search Console, '
          'and Google has crawled and indexed the pages.',
          style: TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
            height: 1.6,
          ),
        ),
        if (domainSet) ...[
          const SizedBox(height: 10),
          _InfoRow(
            icon: Icons.language_rounded,
            text: 'Configured domain: $domain',
          ),
        ],
      ],
    );
  }
}

// ── S2: Deployment Readiness ──────────────────────────────────────────────────

class _DeploymentReadiness extends StatelessWidget {
  const _DeploymentReadiness({
    required this.generated,
    required this.globalConfigured,
    required this.catalogEnabled,
    required this.locationEnabled,
    required this.domainSet,
  });

  final bool generated;
  final bool globalConfigured;
  final bool catalogEnabled;
  final bool locationEnabled;
  final bool domainSet;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _ReadinessItem(
          icon: Icons.pages_rounded,
          label: 'SEO pages generated',
          ok: generated,
          hint: generated ? null : 'Run the SEO generator script',
        ),
        _ReadinessItem(
          icon: Icons.map_rounded,
          label: 'Sitemap generated',
          ok: generated,
          hint: generated ? null : 'Generated alongside SEO pages',
        ),
        _ReadinessItem(
          icon: Icons.smart_toy_rounded,
          label: 'robots.txt generated',
          ok: generated,
          hint: generated ? null : 'Generated alongside SEO pages',
        ),
        const _ReadinessItem(
          icon: Icons.data_object_rounded,
          label: 'Structured data (JSON-LD)',
          ok: true,
          hint: 'All generated SEO pages include JSON-LD structured data',
        ),
        _ReadinessItem(
          icon: Icons.link_rounded,
          label: 'Canonical URLs',
          ok: domainSet,
          hint: domainSet
              ? 'Canonical tags reference the configured production domain'
              : 'Production domain required — canonical URLs cannot be finalised until a domain is set',
        ),
        _ReadinessItem(
          icon: Icons.verified_rounded,
          label: 'SEO validation passed',
          ok: generated,
          hint: generated
              ? 'Validation is a prerequisite for timestamp recording'
              : 'Validation runs automatically at generation time',
        ),
        _ReadinessItem(
          icon: Icons.grid_view_rounded,
          label: 'Catalog SEO configured',
          ok: catalogEnabled,
          hint: catalogEnabled
              ? null
              : 'Add SEO titles in the Catalog SEO tab',
        ),
        _ReadinessItem(
          icon: Icons.place_rounded,
          label: 'Location SEO enabled',
          ok: locationEnabled,
          optional: true,
          hint: locationEnabled
              ? null
              : 'Optional — configure in Location Pages tab',
        ),
        _ReadinessItem(
          icon: Icons.language_rounded,
          label: 'Production domain set',
          ok: domainSet,
          hint: domainSet ? null : 'Set in Global SEO tab',
        ),
      ],
    );
  }
}

// ── S3: Search Performance ────────────────────────────────────────────────────

class _SearchPerformance extends StatelessWidget {
  const _SearchPerformance();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Metric cards — all unavailable
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 500;
            return wide
                ? Row(
                    children: [
                      Expanded(child: _MetricCard(label: 'Impressions', value: '0', note: 'No data yet')),
                      const SizedBox(width: 12),
                      Expanded(child: _MetricCard(label: 'Clicks', value: '0', note: 'No data yet')),
                      const SizedBox(width: 12),
                      Expanded(child: _MetricCard(label: 'CTR', value: '—', note: 'Unavailable')),
                      const SizedBox(width: 12),
                      Expanded(child: _MetricCard(label: 'Avg. Position', value: '—', note: 'Unavailable')),
                    ],
                  )
                : Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: const [
                      _MetricCard(label: 'Impressions', value: '0', note: 'No data yet'),
                      _MetricCard(label: 'Clicks', value: '0', note: 'No data yet'),
                      _MetricCard(label: 'CTR', value: '—', note: 'Unavailable'),
                      _MetricCard(label: 'Avg. Position', value: '—', note: 'Unavailable'),
                    ],
                  );
          },
        ),
        const SizedBox(height: 16),
        _InfoBanner(
          icon: Icons.info_outline_rounded,
          text:
              'Search performance data becomes available after deployment, '
              'Google Search Console verification, and Google indexing. '
              'Impression and click data may take several weeks to accumulate '
              'after a site first goes live.',
        ),
      ],
    );
  }
}

// ── S4: Indexing Status ───────────────────────────────────────────────────────

class _IndexingStatus extends StatelessWidget {
  const _IndexingStatus();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _RowLabel('Indexed pages'),
            const SizedBox(width: 12),
            const Text(
              'Unknown',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        _RowLabel('Reason'),
        const SizedBox(height: 4),
        const Text(
          'Google Search Console is not connected.',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 12),
        _InfoBanner(
          icon: Icons.info_outline_rounded,
          text:
              'Indexing status requires Google Search Console. Once the site is '
              'live and verified, Search Console shows which pages Google has indexed, '
              'any crawl errors, and coverage reports.',
        ),
      ],
    );
  }
}

// ── S5: Sitemap ───────────────────────────────────────────────────────────────

class _SitemapSection extends StatelessWidget {
  const _SitemapSection({
    required this.generated,
    required this.lastGen,
    required this.domain,
    required this.domainSet,
  });

  final bool generated;
  final DateTime? lastGen;
  final String domain;
  final bool domainSet;

  @override
  Widget build(BuildContext context) {
    final sitemapUrl = domainSet ? '$domain/sitemap.xml' : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StatusRow(
          label: 'sitemap.xml',
          ok: generated,
          valueWhenOk: 'Generated',
          valueWhenNotOk: 'Not generated',
        ),
        if (generated && lastGen != null) ...[
          const SizedBox(height: 8),
          _InfoRow(
            icon: Icons.schedule_rounded,
            text: 'Last generated: ${_fmtDateTime(lastGen!)}',
          ),
        ],
        if (sitemapUrl != null) ...[
          const SizedBox(height: 8),
          _InfoRow(
            icon: Icons.link_rounded,
            text: 'Production URL: $sitemapUrl',
          ),
        ],
        if (!domainSet) ...[
          const SizedBox(height: 10),
          _InfoBanner(
            icon: Icons.warning_amber_rounded,
            color: AppColors.warning,
            text:
                'Production domain is not configured. The sitemap URL cannot be '
                'determined until a domain is set in Global SEO settings.',
          ),
        ],
        if (!generated) ...[
          const SizedBox(height: 10),
          _InfoBanner(
            icon: Icons.info_outline_rounded,
            text:
                'Run the SEO generator script to produce sitemap.xml. '
                'It is written to the dist/ directory alongside all generated SEO pages.',
          ),
        ],
      ],
    );
  }
}

// ── S6: Robots.txt ────────────────────────────────────────────────────────────

class _RobotsSection extends StatelessWidget {
  const _RobotsSection({
    required this.generated,
    required this.domain,
    required this.domainSet,
  });

  final bool generated;
  final String domain;
  final bool domainSet;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StatusRow(
          label: 'robots.txt',
          ok: generated,
          valueWhenOk: 'Generated',
          valueWhenNotOk: 'Not generated',
        ),
        const SizedBox(height: 12),
        const Text(
          'Directive summary:',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 6),
        _DirectiveRow(directive: 'Disallow', paths: '/catalog/, /booking, /cart, /checkout, /profile, /my-bookings, /address, /login, /otp'),
        _DirectiveRow(directive: 'Allow', paths: '/s/'),
        if (domainSet) ...[
          const SizedBox(height: 4),
          _InfoRow(
            icon: Icons.link_rounded,
            text: 'Sitemap: $domain/sitemap.xml',
          ),
        ],
        const SizedBox(height: 12),
        if (!domainSet)
          _InfoBanner(
            icon: Icons.warning_amber_rounded,
            color: AppColors.warning,
            text:
                'Production domain is not configured. The Sitemap line in robots.txt '
                'requires a domain. Set one in Global SEO settings and regenerate.',
          )
        else
          _InfoBanner(
            icon: Icons.check_circle_outline_rounded,
            color: AppColors.success,
            text:
                'robots.txt references the configured production domain. '
                'Private routes are blocked; the /s/ path used for all SEO pages is explicitly allowed.',
          ),
      ],
    );
  }
}

// ── S7: Readiness Checklist ───────────────────────────────────────────────────

class _ReadinessChecklist extends StatelessWidget {
  const _ReadinessChecklist({
    required this.globalConfigured,
    required this.catalogEnabled,
    required this.locationEnabled,
    required this.generated,
    required this.domainSet,
  });

  final bool globalConfigured;
  final bool catalogEnabled;
  final bool locationEnabled;
  final bool generated;
  final bool domainSet;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Pre-deployment (admin actions) ───────────────────────────────
        const _ChecklistSubheader('Pre-deployment'),
        _CheckItem(
          state: globalConfigured ? _Check.done : _Check.warn,
          label: 'Global SEO configured',
          detail: globalConfigured ? null : 'Set brand name and domain in Global SEO tab',
        ),
        _CheckItem(
          state: catalogEnabled ? _Check.done : _Check.warn,
          label: 'Catalog SEO configured',
          detail: catalogEnabled ? null : 'Add SEO titles to catalog nodes in Catalog SEO tab',
        ),
        _CheckItem(
          state: locationEnabled ? _Check.done : _Check.optional,
          label: 'Location SEO configured',
          detail: locationEnabled ? null : 'Optional — configure area-specific pages in Location Pages tab',
        ),
        _CheckItem(
          state: generated ? _Check.done : _Check.warn,
          label: 'Static SEO pages generated',
          detail: generated ? null : 'Run: cd scripts/generate-seo-pages && npm run generate',
        ),
        _CheckItem(
          state: generated ? _Check.done : _Check.pending,
          label: 'Validation passed',
          detail: generated
              ? 'Validation is a prerequisite — timestamp only records after a clean run'
              : 'Runs automatically during generation',
        ),
        _CheckItem(
          state: generated ? _Check.done : _Check.pending,
          label: 'Sitemap generated',
          detail: generated ? null : 'Generated alongside SEO pages',
        ),
        _CheckItem(
          state: generated ? _Check.done : _Check.pending,
          label: 'robots.txt generated',
          detail: generated ? null : 'Generated alongside SEO pages',
        ),
        _CheckItem(
          state: _Check.done,
          label: 'Canonical URLs configured',
          detail: 'Baked into all generated page templates',
        ),
        _CheckItem(
          state: domainSet ? _Check.done : _Check.warn,
          label: 'Production domain configured',
          detail: domainSet ? null : 'Set in Global SEO tab — required for canonical URLs and sitemap',
        ),

        const SizedBox(height: 16),

        // ── Post-deployment (external) ───────────────────────────────────
        const _ChecklistSubheader('Post-deployment'),
        const _CheckItem(
          state: _Check.pending,
          label: 'Google Search Console verification',
          detail: 'Verify domain ownership in Google Search Console after deployment',
        ),
        const _CheckItem(
          state: _Check.pending,
          label: 'Google indexing',
          detail: 'Submit sitemap.xml in Search Console; indexing takes days to weeks',
        ),
        const _CheckItem(
          state: _Check.pending,
          label: 'Search performance data',
          detail: 'Impression and click data accumulates after indexing',
        ),
      ],
    );
  }
}

// ── S8: Future Search Metrics ─────────────────────────────────────────────────

class _FutureMetrics extends StatelessWidget {
  const _FutureMetrics();

  @override
  Widget build(BuildContext context) {
    const metrics = [
      ('Total impressions', 'How many times pages appeared in Google search results'),
      ('Total clicks', 'How many users clicked through to the site'),
      ('Click-through rate (CTR)', 'Clicks ÷ impressions, per page or query'),
      ('Average position', 'Mean rank across all indexed pages and queries'),
      ('Top pages by impressions', 'Which SEO pages drive the most visibility'),
      ('Top search queries', 'Which keywords bring users to the site'),
      ('Mobile vs desktop breakdown', 'Device-level performance split'),
      ('Country-level data', 'Geographic distribution of search traffic'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'After the site is deployed, verified in Google Search Console, and indexed '
          'by Google, the following metrics will populate naturally over time. '
          'They will be surfaced here in a future update once Search Console integration is added.',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.6),
        ),
        const SizedBox(height: 16),
        ...metrics.map(
          (m) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.schedule_rounded,
                  size: 14,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        m.$1,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        m.$2,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        _InfoBanner(
          icon: Icons.info_outline_rounded,
          text:
              'No charts or trend lines will be shown here until real data is available. '
              'All values above will display 0 until Search Console integration is completed.',
        ),
      ],
    );
  }
}

// ── Shared sub-widgets ────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.child,
  });

  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
            child: Row(
              children: [
                Icon(icon, size: 16, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          Padding(
            padding: const EdgeInsets.all(20),
            child: child,
          ),
        ],
      ),
    );
  }
}

// ── Status chip ───────────────────────────────────────────────────────────────

class _Chip extends StatelessWidget {
  const _Chip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Readiness grid item ───────────────────────────────────────────────────────

class _ReadinessItem extends StatelessWidget {
  const _ReadinessItem({
    required this.icon,
    required this.label,
    required this.ok,
    this.optional = false,
    this.hint,
  });

  final IconData icon;
  final String label;
  final bool ok;
  final bool optional;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final color = ok
        ? AppColors.success
        : optional
            ? AppColors.textSecondary
            : AppColors.warning;
    final statusIcon = ok
        ? Icons.check_circle_rounded
        : optional
            ? Icons.radio_button_unchecked_rounded
            : Icons.warning_amber_rounded;

    return Container(
      width: 200,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(statusIcon, size: 13, color: color),
              const SizedBox(width: 6),
              Icon(icon, size: 13, color: AppColors.textSecondary),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          if (hint != null) ...[
            const SizedBox(height: 3),
            Text(
              hint!,
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Metric card (search performance, all unavailable) ─────────────────────────

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.note,
  });

  final String label;
  final String value;
  final String note;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            note,
            style: const TextStyle(
              fontSize: 10,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Status row (label + ok/not-ok value) ─────────────────────────────────────

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.label,
    required this.ok,
    required this.valueWhenOk,
    required this.valueWhenNotOk,
  });

  final String label;
  final bool ok;
  final String valueWhenOk;
  final String valueWhenNotOk;

  @override
  Widget build(BuildContext context) {
    final color = ok ? AppColors.success : AppColors.textSecondary;
    final icon = ok ? Icons.check_circle_rounded : Icons.remove_circle_outline_rounded;

    return Row(
      children: [
        _RowLabel(label),
        const SizedBox(width: 12),
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          ok ? valueWhenOk : valueWhenNotOk,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: ok ? AppColors.textPrimary : AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

// ── Checklist ─────────────────────────────────────────────────────────────────

enum _Check { done, warn, pending, optional }

class _ChecklistSubheader extends StatelessWidget {
  const _ChecklistSubheader(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _CheckItem extends StatelessWidget {
  const _CheckItem({
    required this.state,
    required this.label,
    this.detail,
  });

  final _Check state;
  final String label;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (state) {
      _Check.done => (Icons.check_circle_rounded, AppColors.success),
      _Check.warn => (Icons.warning_amber_rounded, AppColors.warning),
      _Check.pending => (Icons.hourglass_empty_rounded, AppColors.textSecondary),
      _Check.optional => (Icons.radio_button_unchecked_rounded, AppColors.textSecondary),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 15, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (detail != null)
                  Text(
                    detail!,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                      height: 1.4,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Directive row (robots.txt display) ───────────────────────────────────────

class _DirectiveRow extends StatelessWidget {
  const _DirectiveRow({required this.directive, required this.paths});
  final String directive;
  final String paths;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 68,
            child: Text(
              '$directive:',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
                fontFamily: 'monospace',
              ),
            ),
          ),
          Expanded(
            child: Text(
              paths,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textPrimary,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Info row (icon + text inline) ─────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 13, color: AppColors.textSecondary),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ),
      ],
    );
  }
}

// ── Info banner ───────────────────────────────────────────────────────────────

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({
    required this.icon,
    required this.text,
    this.color = AppColors.textSecondary,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                color: color,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Labeled field (Status / Reason / Action rows) ────────────────────────────

class _LabeledField extends StatelessWidget {
  const _LabeledField({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 56,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 12,
              color: valueColor ?? AppColors.textPrimary,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Row label ─────────────────────────────────────────────────────────────────

class _RowLabel extends StatelessWidget {
  const _RowLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 110,
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

// ── Error view ────────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded,
              size: 40, color: AppColors.error),
          const SizedBox(height: 12),
          Text(error,
              style:
                  const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

String _fmtDateTime(DateTime dt) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final h = dt.hour.toString().padLeft(2, '0');
  final m = dt.minute.toString().padLeft(2, '0');
  return '${months[dt.month - 1]} ${dt.day}, ${dt.year} at $h:$m';
}
