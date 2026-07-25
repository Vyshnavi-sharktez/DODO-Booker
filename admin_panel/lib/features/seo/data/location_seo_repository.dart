import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/models/location_node_seo.dart';

class LocationSeoRepository {
  const LocationSeoRepository(this._supabase);
  final SupabaseClient _supabase;

  /// Returns all location SEO configs for [areaId], ordered by node name.
  Future<List<LocationNodeSeo>> fetchForArea(String areaId) async {
    final data = await _supabase
        .from('location_node_seo')
        .select()
        .eq('area_id', areaId)
        .order('created_at', ascending: true);
    return (data as List<dynamic>)
        .map((r) => LocationNodeSeo.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  /// Upserts a location SEO config for the given [areaId] × [nodeId] pair.
  /// Conflicts on the (area_id, node_id) UNIQUE constraint — safe to call
  /// repeatedly (updates the existing row).
  Future<LocationNodeSeo> upsert({
    required String areaId,
    required String nodeId,
    String? seoTitle,
    String? seoDescription,
    String? ogTitle,
    String? ogDescription,
    String? ogImageUrl,
    String? seoContent,
    required bool noindex,
  }) async {
    final data = await _supabase
        .from('location_node_seo')
        .upsert(
          {
            'area_id': areaId,
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
            'seo_content': seoContent?.trim().isEmpty == true
                ? null
                : seoContent?.trim(),
            'noindex': noindex,
          },
          onConflict: 'area_id,node_id',
        )
        .select()
        .single();
    return LocationNodeSeo.fromMap(data);
  }

  /// Deletes the location SEO config with the given [id].
  Future<void> delete(String id) async {
    await _supabase.from('location_node_seo').delete().eq('id', id);
  }
}
