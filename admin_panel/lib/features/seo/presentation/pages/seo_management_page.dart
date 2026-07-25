import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Page header ────────────────────────────────────────────────────
          _PageHeader(tabController: _tabController),
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
  const _PageHeader({required this.tabController});
  final TabController tabController;

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
                Column(
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

