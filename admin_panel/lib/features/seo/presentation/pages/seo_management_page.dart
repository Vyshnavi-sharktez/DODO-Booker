import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../application/providers/seo_providers.dart';
import '../../data/seo_repository.dart';
import '../widgets/catalog_seo_tab.dart';
import '../widgets/global_seo_tab.dart';
import '../widgets/location_pages_tab.dart';
import '../widgets/search_insights_tab.dart';
import '../widgets/seo_overview_card.dart';

/// SEO Management — Admin Panel page.
///
/// Global SEO (tab 0), Catalog SEO (tab 1), Location Pages (tab 2),
/// Search Insights (tab 3) — all implemented.
///
/// Accessible via /dashboard/seo — guarded by settings.manage RBAC.
class SeoManagementPage extends ConsumerStatefulWidget {
  const SeoManagementPage({super.key});

  @override
  ConsumerState<SeoManagementPage> createState() =>
      _SeoManagementPageState();
}

class _SeoManagementPageState extends ConsumerState<SeoManagementPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _generating = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const _GenerateConfirmDialog(),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _generating = true);

    final SeoGenerationResult result =
        await ref.read(seoRepositoryProvider).generateSeoPages();

    if (!mounted) return;
    setState(() => _generating = false);

    if (result.success) {
      ref.invalidate(seoGlobalSettingsProvider);
      ref.invalidate(seoCoverageStatsProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('SEO pages generated successfully.'),
          backgroundColor: AppColors.success,
          duration: Duration(seconds: 4),
        ),
      );
    } else {
      await showDialog<void>(
        context: context,
        builder: (_) => _GenerationErrorDialog(
          error: result.error ?? 'Unknown error during generation.',
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Page header ────────────────────────────────────────────────────
          _PageHeader(
            tabController: _tabController,
            isGenerating: _generating,
            onGenerate: _generate,
          ),
          // ── SEO coverage overview ──────────────────────────────────────────
          const SeoOverviewCard(),
          // ── Tab body ───────────────────────────────────────────────────────
          Expanded(
            child: TabBarView(
              controller: _tabController,
              // Disable swipe on wide-canvas admin UI — accidental swipes
              // lose unsaved form state.
              physics: const NeverScrollableScrollPhysics(),
              children: const [
                GlobalSeoTab(),
                CatalogSeoTab(),
                LocationPagesTab(),
                SearchInsightsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Page header ────────────────────────────────────────────────────────────────

class _PageHeader extends StatelessWidget {
  const _PageHeader({
    required this.tabController,
    required this.isGenerating,
    required this.onGenerate,
  });
  final TabController tabController;
  final bool isGenerating;
  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title row
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 8),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.travel_explore_rounded,
                    color: AppColors.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'SEO Management',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        'Manage search engine optimisation settings for the platform',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                _GenerateButton(
                  isGenerating: isGenerating,
                  onGenerate: onGenerate,
                ),
              ],
            ),
          ),
          // Tab bar
          TabBar(
            controller: tabController,
            labelPadding: const EdgeInsets.symmetric(horizontal: 20),
            indicatorColor: AppColors.primary,
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textSecondary,
            labelStyle: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
            unselectedLabelStyle: const TextStyle(
              fontWeight: FontWeight.w400,
              fontSize: 13,
            ),
            tabs: const [
              Tab(text: 'Global SEO'),
              Tab(text: 'Catalog SEO'),
              Tab(text: 'Location Pages'),
              Tab(text: 'Search Insights'),
            ],
          ),
          const Divider(height: 1, color: AppColors.border),
        ],
      ),
    );
  }
}

// ── Generate button ────────────────────────────────────────────────────────────

class _GenerateButton extends StatelessWidget {
  const _GenerateButton({
    required this.isGenerating,
    required this.onGenerate,
  });
  final bool isGenerating;
  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: isGenerating ? null : onGenerate,
      icon: isGenerating
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Icon(Icons.refresh_rounded, size: 16),
      label: Text(isGenerating ? 'Generating…' : 'Generate SEO Pages'),
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.5),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        textStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ── Dialogs ───────────────────────────────────────────────────────────────────

class _GenerateConfirmDialog extends StatelessWidget {
  const _GenerateConfirmDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Generate SEO Pages?'),
      content: const Text(
        'This will regenerate all SEO assets — HTML pages, sitemap.xml, '
        'robots.txt, structured data, canonical URLs, and location pages — '
        'using the latest SEO configuration.\n\n'
        'The generator server must be running:\n'
        '  cd scripts/generate-seo-pages && node server.js',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
          ),
          child: const Text('Generate'),
        ),
      ],
    );
  }
}

class _GenerationErrorDialog extends StatelessWidget {
  const _GenerationErrorDialog({required this.error});
  final String error;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: AppColors.error),
          const SizedBox(width: 8),
          const Text('Generation Failed'),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 320),
        child: SingleChildScrollView(
          child: SelectableText(
            error,
            style: const TextStyle(
              fontSize: 12,
              fontFamily: 'monospace',
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
