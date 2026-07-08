import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/supabase_config.dart';
import '../../../models/faq_model.dart';
import '../models/catalog_node_model.dart';

class CatalogService {
  static bool get _ready =>
      SupabaseConfig.supabaseUrl.isNotEmpty &&
      SupabaseConfig.supabaseAnonKey.isNotEmpty;

  static SupabaseClient get _db => Supabase.instance.client;

  Future<List<CatalogNodeModel>> fetchRootNodes() async {
    if (!_ready) return [];
    try {
      final data = await _db
          .from('catalog_nodes_view')
          .select()
          .isFilter('parent_id', null)
          .eq('is_active', true)
          .order('sort_order', ascending: true)
          .order('name', ascending: true);
      return (data as List)
          .map((e) => CatalogNodeModel.fromMap(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[CatalogService] fetchRootNodes error: $e');
      return [];
    }
  }

  Future<CatalogNodeModel?> fetchNode(String id) async {
    if (!_ready) return null;
    try {
      final data = await _db
          .from('catalog_nodes_view')
          .select()
          .eq('id', id)
          .maybeSingle();
      if (data == null) return null;
      return CatalogNodeModel.fromMap(data);
    } catch (e) {
      debugPrint('[CatalogService] fetchNode($id) error: $e');
      return null;
    }
  }

  Future<List<CatalogNodeModel>> fetchChildren(String parentId) async {
    if (!_ready) return [];
    try {
      final data = await _db
          .from('catalog_nodes_view')
          .select()
          .eq('parent_id', parentId)
          .eq('is_active', true)
          .order('sort_order', ascending: true)
          .order('name', ascending: true);
      return (data as List)
          .map((e) => CatalogNodeModel.fromMap(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[CatalogService] fetchChildren($parentId) error: $e');
      return [];
    }
  }

  /// Fetches FAQs by node_id (backfilled in Phase-1 migration for all
  /// migrated services; also covers new catalog-only nodes).
  Future<List<FaqModel>> fetchFaqsForNode(String nodeId) async {
    if (!_ready) return [];
    try {
      final data = await _db
          .from('service_faqs')
          .select()
          .eq('node_id', nodeId);
      return (data as List)
          .map((e) => FaqModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[CatalogService] fetchFaqsForNode($nodeId) error: $e');
      return [];
    }
  }

  /// Full-text search across all active catalog nodes.
  Future<List<CatalogNodeModel>> searchNodes(String query) async {
    if (!_ready || query.trim().isEmpty) return [];
    try {
      final data = await _db
          .from('catalog_nodes_view')
          .select()
          .eq('is_active', true)
          .ilike('name', '%$query%')
          .order('sort_order', ascending: true)
          .limit(25);
      return (data as List)
          .map((e) => CatalogNodeModel.fromMap(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[CatalogService] searchNodes error: $e');
      return [];
    }
  }
}
