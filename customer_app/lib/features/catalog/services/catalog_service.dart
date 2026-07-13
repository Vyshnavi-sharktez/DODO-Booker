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

  /// All active top-level catalog items (no parent category).
  Future<List<CatalogNodeModel>> fetchRootNodes() async {
    if (!_ready) return [];
    try {
      final data = await _db
          .from('catalog_nodes_view')
          .select()
          .eq('is_root_node', true)
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

  /// Active direct children of [parentId], ordered by sort_order.
  /// Uses the get_catalog_node_children() DB function which joins
  /// through the catalog_node_relationships table.
  Future<List<CatalogNodeModel>> fetchChildren(String parentId) async {
    if (!_ready) return [];
    try {
      final data = await _db.rpc(
        'get_catalog_node_children',
        params: {'p_parent_id': parentId},
      );
      return (data as List)
          .map((e) => CatalogNodeModel.fromMap(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[CatalogService] fetchChildren($parentId) error: $e');
      return [];
    }
  }

  /// FAQs for a catalog item (queried by node_id).
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

  /// Full-text search across all active catalog items.
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
