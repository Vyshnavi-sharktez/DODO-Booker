import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/models/catalog_node_seo.dart';
import '../domain/models/seo_coverage_stats.dart';
import '../domain/models/seo_global_settings.dart';

/// Result of [SeoRepository.generateSeoPages].
class SeoGenerationResult {
  const SeoGenerationResult({
    required this.success,
    required this.output,
    this.error,
  });

  final bool success;
  final String output;

  /// Non-null when [success] is false.
  final String? error;
}

class SeoRepository {
  final SupabaseClient _supabase;

  const SeoRepository(this._supabase);

  // ── Global Settings ────────────────────────────────────────────────────────

  /// Returns the singleton global SEO row, or null if the admin has not
  /// saved one yet.
  Future<SeoGlobalSettings?> fetchGlobalSettings() async {
    final data = await _supabase
        .from('seo_global_settings')
        .select()
        .eq('id', 'global')
        .maybeSingle();
    if (data == null) return null;
    return SeoGlobalSettings.fromMap(data);
  }

  /// Upserts the singleton global SEO row.
  /// Empty strings are coerced to null so the DB stores clean nulls.
  Future<SeoGlobalSettings> upsertGlobalSettings({
    String? brandName,
    String? brandTagline,
    String? productionDomain,
    String? defaultOgImageUrl,
    String? titleTemplate,
    String? homepageSeoTitle,
    String? homepageSeoDescription,
  }) async {
    final data = await _supabase
        .from('seo_global_settings')
        .upsert(
          {
            'id': 'global',
            'brand_name':
                brandName?.trim().isEmpty == true ? null : brandName?.trim(),
            'brand_tagline': brandTagline?.trim().isEmpty == true
                ? null
                : brandTagline?.trim(),
            'production_domain': productionDomain?.trim().isEmpty == true
                ? null
                : productionDomain?.trim(),
            'default_og_image_url': defaultOgImageUrl?.trim().isEmpty == true
                ? null
                : defaultOgImageUrl?.trim(),
            'title_template': titleTemplate?.trim().isEmpty == true
                ? null
                : titleTemplate?.trim(),
            'homepage_seo_title': homepageSeoTitle?.trim().isEmpty == true
                ? null
                : homepageSeoTitle?.trim(),
            'homepage_seo_description':
                homepageSeoDescription?.trim().isEmpty == true
                    ? null
                    : homepageSeoDescription?.trim(),
          },
          onConflict: 'id',
        )
        .select()
        .single();
    return SeoGlobalSettings.fromMap(data);
  }

  // ── Coverage Stats ────────────────────────────────────────────────────────

  /// Returns aggregate SEO coverage counts for the overview card.
  ///
  /// Runs independent queries in parallel. The location_node_seo table may not
  /// exist yet (migration pending); those counts default to zero on error.
  Future<SeoCoverageStats> fetchSeoCoverageStats() async {
    final results = await Future.wait([
      // [0] Catalog nodes with SEO configured (seo_title set, not noindex)
      _supabase
          .from('catalog_node_seo')
          .select('node_id')
          .eq('noindex', false)
          .not('seo_title', 'is', null)
          .neq('seo_title', ''),
      // [1] Total active catalog nodes
      _supabase.from('catalog_nodes_view').select('id').eq('is_active', true),
      // [2] Latest catalog_node_seo update (for staleness)
      _supabase
          .from('catalog_node_seo')
          .select('updated_at')
          .order('updated_at', ascending: false)
          .limit(1),
      // [3] Total active service areas
      _supabase
          .from('service_availability_areas')
          .select('id')
          .eq('is_active', true),
    ]);

    final configuredCatalog = (results[0] as List).length;
    final totalNodes = (results[1] as List).length;
    final totalAreas = (results[3] as List).length;

    DateTime? latestUpdatedAt;
    final catalogLatest = results[2] as List;
    if (catalogLatest.isNotEmpty) {
      latestUpdatedAt = DateTime.tryParse(
        catalogLatest.first['updated_at'] as String,
      );
    }

    // Location SEO — table may not exist until migration is applied.
    int configuredLocation = 0;
    try {
      final locationRows = await _supabase
          .from('location_node_seo')
          .select('node_id')
          .eq('noindex', false)
          .not('seo_title', 'is', null)
          .neq('seo_title', '');
      configuredLocation = (locationRows as List).length;

      final locationLatest = await _supabase
          .from('location_node_seo')
          .select('updated_at')
          .order('updated_at', ascending: false)
          .limit(1);
      if ((locationLatest as List).isNotEmpty) {
        final t = DateTime.tryParse(
          locationLatest.first['updated_at'] as String,
        );
        if (t != null &&
            (latestUpdatedAt == null || t.isAfter(latestUpdatedAt))) {
          latestUpdatedAt = t;
        }
      }
    } catch (_) {
      // Ignore — location_node_seo table not yet migrated.
    }

    return SeoCoverageStats(
      configuredCatalogCount: configuredCatalog,
      totalActiveCatalogNodes: totalNodes,
      configuredLocationCount: configuredLocation,
      totalActiveAreas: totalAreas,
      latestSeoUpdatedAt: latestUpdatedAt,
    );
  }

  // ── Catalog Node SEO ──────────────────────────────────────────────────────

  /// Returns the SEO configuration for [nodeId], or null if not yet configured.
  Future<CatalogNodeSeo?> fetchNodeSeo(String nodeId) async {
    final data = await _supabase
        .from('catalog_node_seo')
        .select()
        .eq('node_id', nodeId)
        .maybeSingle();
    if (data == null) return null;
    return CatalogNodeSeo.fromMap(data);
  }

  /// Returns a map of nodeId → CatalogNodeSeo for ALL configured nodes.
  /// Used by the catalog tree to overlay health status without N+1 queries.
  Future<Map<String, CatalogNodeSeo>> fetchAllNodeSeo() async {
    final data = await _supabase.from('catalog_node_seo').select();
    return {
      for (final row in data as List<dynamic>)
        (row as Map<String, dynamic>)['node_id'] as String:
            CatalogNodeSeo.fromMap(row),
    };
  }

  // ── SEO Generation ────────────────────────────────────────────────────────

  /// Triggers the SEO generator by calling the local server (server.js).
  ///
  /// The server spawns `node index.js` and waits for completion. Returns a
  /// [SeoGenerationResult] — never throws; connection/timeout errors are
  /// surfaced as a failed result with a human-readable [SeoGenerationResult.error].
  ///
  /// Prerequisites:
  ///   cd scripts/generate-seo-pages && node server.js
  Future<SeoGenerationResult> generateSeoPages() async {
    const url = 'http://localhost:4040/generate';
    http.Response response;
    try {
      response = await http
          .post(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(minutes: 5));
    } on TimeoutException {
      return const SeoGenerationResult(
        success: false,
        output: '',
        error: 'Generation timed out after 5 minutes.',
      );
    } catch (_) {
      return const SeoGenerationResult(
        success: false,
        output: '',
        error:
            'Could not connect to the generator server.\n\n'
            'Start it first:\n'
            '  cd scripts/generate-seo-pages\n'
            '  node server.js',
      );
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return SeoGenerationResult(
      success: response.statusCode == 200 &&
          (body['success'] as bool? ?? false),
      output: body['output'] as String? ?? '',
      error: body['error'] as String?,
    );
  }

  // ── Catalog Node SEO ──────────────────────────────────────────────────────

  /// Upserts the SEO configuration for [nodeId].
  /// Conflicts on node_id (UNIQUE constraint) — safe to call repeatedly.
  Future<CatalogNodeSeo> upsertNodeSeo({
    required String nodeId,
    String? seoTitle,
    String? seoDescription,
    String? ogTitle,
    String? ogDescription,
    String? ogImageUrl,
    String? seoContent,
    String? primarySearchTopic,
    required bool noindex,
  }) async {
    final data = await _supabase
        .from('catalog_node_seo')
        .upsert(
          {
            'node_id': nodeId,
            'seo_title':
                seoTitle?.trim().isEmpty == true ? null : seoTitle?.trim(),
            'seo_description': seoDescription?.trim().isEmpty == true
                ? null
                : seoDescription?.trim(),
            'og_title':
                ogTitle?.trim().isEmpty == true ? null : ogTitle?.trim(),
            'og_description': ogDescription?.trim().isEmpty == true
                ? null
                : ogDescription?.trim(),
            'og_image_url':
                ogImageUrl?.trim().isEmpty == true ? null : ogImageUrl?.trim(),
            'seo_content':
                seoContent?.trim().isEmpty == true ? null : seoContent?.trim(),
            'primary_search_topic':
                primarySearchTopic?.trim().isEmpty == true
                    ? null
                    : primarySearchTopic?.trim(),
            'noindex': noindex,
          },
          onConflict: 'node_id',
        )
        .select()
        .single();
    return CatalogNodeSeo.fromMap(data);
  }
}
