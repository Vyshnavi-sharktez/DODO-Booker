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

  /// Fetches a node and resolves its displayed parent name from the given
  /// parentId instead of catalog_nodes_view's canonical first parent.
  /// Use this when a specific parent context is known (e.g. notification tap).
  Future<CatalogNodeModel?> fetchNodeWithParent(
      String nodeId, String parentId) async {
    if (!_ready) return null;
    try {
      final results = await Future.wait([fetchNode(nodeId), fetchNode(parentId)]);
      final node = results[0];
      final parent = results[1];
      if (node == null) return null;
      if (parent == null) return node;
      return node.copyWith(parentName: parent.name);
    } catch (e) {
      debugPrint('[CatalogService] fetchNodeWithParent($nodeId, $parentId) error: $e');
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
          .eq('service_id', nodeId)
          .order('sort_order', ascending: true);
      return (data as List)
          .map((e) => FaqModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[CatalogService] fetchFaqsForNode($nodeId) error: $e');
      return [];
    }
  }

  /// Answered customer questions for a node, scoped to [parentNodeId].
  /// Only questions asked within the same parent context are returned, so a
  /// shared sub-service (e.g. "AC Cleaning") shows distinct Q&A sets under
  /// "Home Cleaning" vs "AC Services".
  Future<List<FaqModel>> fetchAnsweredQuestionsForNode(
      String nodeId, String? parentNodeId) async {
    if (!_ready) return [];
    try {
      var query = _db
          .from('customer_questions')
          .select('id, question, answer')
          .eq('service_id', nodeId)
          .eq('status', 'answered');
      if (parentNodeId != null) {
        query = query.eq('parent_node_id', parentNodeId);
      } else {
        query = query.filter('parent_node_id', 'is', null);
      }
      final data = await query.order('answered_at', ascending: true);
      return (data as List)
          .map((e) => FaqModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[CatalogService] fetchAnsweredQuestionsForNode($nodeId) error: $e');
      return [];
    }
  }

  /// Submits a customer question for a service and notifies admins.
  Future<void> submitQuestion({
    required String serviceId,
    String? parentNodeId,
    required String customerId,
    String? customerName,
    String? customerPhone,
    required String question,
  }) async {
    if (!_ready) return;
    await _db.from('customer_questions').insert({
      'service_id': serviceId,
      if (parentNodeId != null) 'parent_node_id': parentNodeId,
      'customer_id': customerId,
      if (customerName != null) 'customer_name': customerName,
      if (customerPhone != null) 'customer_phone': customerPhone,
      'question': question,
      'status': 'pending',
    });
    // Notify all admins in real-time.
    final preview =
        question.length > 80 ? '${question.substring(0, 80)}…' : question;
    final who = customerName?.isNotEmpty == true ? customerName! : 'A customer';
    await _db.from('notifications').insert({
      'user_type': 'admin',
      'title': 'New Customer Question',
      'message': '$who asked: "$preview"',
      'notification_type': 'new_customer_question',
      'is_read': false,
      'entity_type': 'customer_question',
      'entity_id': serviceId,
    });
  }

  /// Checks the effective availability of [nodeId] accessed via [parentId].
  /// Uses check_node_availability RPC which walks the catalog ancestry path.
  /// Returns (status: 'active'|'unavailable'|'hidden', message: text|null).
  /// Falls back to active on any error so the UI never blocks on a failed check.
  ///
  /// Pass [lat]/[lng] to also enforce location restrictions. When null, the
  /// location check is skipped and only the general status is returned.
  Future<({String status, String? message})> checkAvailability(
    String nodeId,
    String? parentId, {
    double? lat,
    double? lng,
  }) async {
    if (!_ready) return (status: 'active', message: null);
    try {
      final result = await _db.rpc('check_node_availability', params: {
        'p_node_id': nodeId,
        'p_parent_id': parentId,
        if (lat != null) 'p_lat': lat,
        if (lng != null) 'p_lng': lng,
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
