import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/application/providers/auth_provider.dart';
import '../../data/seo_repository.dart';
import '../../domain/models/catalog_node_seo.dart';
import '../../domain/models/seo_coverage_stats.dart';
import '../../domain/models/seo_global_settings.dart';

// ── Repository ─────────────────────────────────────────────────────────────────

final seoRepositoryProvider = Provider<SeoRepository>((ref) {
  return SeoRepository(ref.watch(supabaseClientProvider));
});

// ── Global Settings ────────────────────────────────────────────────────────────

/// Loads the singleton global SEO row.
/// Returns null when the admin has not saved one yet.
/// Invalidate after upsert to force a fresh fetch.
final seoGlobalSettingsProvider =
    FutureProvider<SeoGlobalSettings?>((ref) async {
  return ref.watch(seoRepositoryProvider).fetchGlobalSettings();
});

// ── Coverage Stats ────────────────────────────────────────────────────────

/// Aggregate SEO coverage counts (configured nodes, areas, location pages).
/// Used by [SeoOverviewCard]. Invalidate after any SEO configuration change.
final seoCoverageStatsProvider =
    FutureProvider<SeoCoverageStats>((ref) async {
  return ref.watch(seoRepositoryProvider).fetchSeoCoverageStats();
});

// ── All-node SEO map ──────────────────────────────────────────────────────────

/// Loads the SEO configuration for EVERY configured catalog node in one query.
/// Keyed by nodeId → CatalogNodeSeo.
/// Used by the catalog list to overlay health status without N+1 fetches.
/// Invalidate after any upsertNodeSeo call to refresh health indicators.
final allNodeSeoMapProvider =
    FutureProvider<Map<String, CatalogNodeSeo>>((ref) async {
  return ref.watch(seoRepositoryProvider).fetchAllNodeSeo();
});
