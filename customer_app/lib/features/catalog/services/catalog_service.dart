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
          .neq('availability_status', 'hidden')
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

  /// Checks the effective availability of [nodeId] accessed via [parentId].
  /// Uses check_node_availability RPC which walks the catalog ancestry path.
  /// Returns (status: 'active'|'unavailable'|'hidden', message: text|null).
  /// Falls back to active on any error so the UI never blocks on a failed check.
  Future<({String status, String? message})> checkAvailability(
    String nodeId,
    String? parentId,
  ) async {
    if (!_ready) return (status: 'active', message: null);
    try {
      final result = await _db.rpc('check_node_availability', params: {
        'p_node_id': nodeId,
        'p_parent_id': parentId,
      });
      if (result == null) return (status: 'active', message: null);
      final map = result as Map<String, dynamic>;
      return (
        status: (map['status'] as String?) ?? 'active',
        message: map['message'] as String?,
      );
    } catch (e) {
      debugPrint('[CatalogService] checkAvailability($nodeId) error: $e');
      return (status: 'active', message: null);
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
