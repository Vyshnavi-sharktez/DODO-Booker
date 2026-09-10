import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/config/supabase_config.dart';
import '../../../models/faq_model.dart';
import '../../vendor_custom_service/models/vendor_custom_service_model.dart';
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

  /// FAQs for a vendor custom service (keyed by custom_service_id).
  Future<List<FaqModel>> fetchFaqsForCustomService(String customServiceId) async {
    if (!_ready) return [];
    try {
      final data = await _db
          .from('service_faqs')
          .select()
          .eq('custom_service_id', customServiceId)
          .order('sort_order', ascending: true);
      return (data as List)
          .map((e) => FaqModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[CatalogService] fetchFaqsForCustomService($customServiceId) error: $e');
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

  /// Submits a customer question for a DODO catalog service and notifies admins.
  Future<void> submitQuestion({
    required String serviceId,
    String? parentNodeId,
    required String customerId,
    String? customerName,
    String? customerPhone,
    required String question,
  }) async {
    if (!_ready) return;
    final questionId = const Uuid().v4();
    await _db.from('customer_questions').insert({
      'id': questionId,
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
      if (parentNodeId != null) 'parent_node_id': parentNodeId,
      'customer_question_id': questionId,
    });
  }

  /// Submits a customer question for a vendor custom service.
  /// Notifies both the owning vendor and admins.
  Future<void> submitCustomServiceQuestion({
    required String customServiceId,
    required String vendorId,
    required String serviceName,
    required String customerId,
    String? customerName,
    String? customerPhone,
    required String question,
  }) async {
    if (!_ready) return;
    final questionId = const Uuid().v4();
    await _db.from('customer_questions').insert({
      'id': questionId,
      'custom_service_id': customServiceId,
      'vendor_id': vendorId,
      'customer_id': customerId,
      if (customerName != null) 'customer_name': customerName,
      if (customerPhone != null) 'customer_phone': customerPhone,
      'question': question,
      'status': 'pending',
    });
    final preview =
        question.length > 80 ? '${question.substring(0, 80)}…' : question;
    final who = customerName?.isNotEmpty == true ? customerName! : 'A customer';
    final notifications = [
      {
        'user_type': 'vendor',
        'user_id': vendorId,
        'title': 'New Customer Question',
        'message': '$who asked about $serviceName: "$preview"',
        'notification_type': 'new_customer_question',
        'is_read': false,
        'entity_type': 'customer_question',
        'entity_id': customServiceId,
        'customer_question_id': questionId,
      },
      {
        'user_type': 'admin',
        'title': 'New Customer Question',
        'message': '$who asked about $serviceName: "$preview"',
        'notification_type': 'new_customer_question',
        'is_read': false,
        'entity_type': 'custom_service_question',
        'entity_id': customServiceId,
        'customer_question_id': questionId,
      },
    ];
    await _db.from('notifications').insert(notifications);
  }

  /// Answered customer questions for a custom service, displayed in the FAQ block.
  Future<List<FaqModel>> fetchAnsweredQuestionsForCustomService(
      String customServiceId) async {
    if (!_ready) return [];
    try {
      final data = await _db
          .from('customer_questions')
          .select('id, question, answer')
          .eq('custom_service_id', customServiceId)
          .eq('status', 'answered')
          .order('answered_at', ascending: true);
      return (data as List)
          .map((e) => FaqModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint(
          '[CatalogService] fetchAnsweredQuestionsForCustomService($customServiceId) error: $e');
      return [];
    }
  }

  /// Fetches a vendor custom service by its ID for deep-link / notification tap.
  Future<VendorCustomServiceModel?> fetchCustomServiceById(
      String customServiceId) async {
    if (!_ready) return null;
    try {
      final data = await _db
          .from('vendor_service_requests')
          .select(
              'id, service_name, description, active_price, image_url, vendor_id, '
              'rating, review_count, included_items, excluded_items, before_after_pairs, '
              'vendors!vendor_id(business_name)')
          .eq('id', customServiceId)
          .inFilter('status', ['completed', 'pending_deletion'])
          .maybeSingle();
      if (data == null) return null;
      final vendor = data['vendors'] as Map<String, dynamic>?;
      final vendorName = (vendor?['business_name'] as String?) ?? '';
      return VendorCustomServiceModel(
        id: data['id'] as String,
        serviceName: data['service_name'] as String,
        description: data['description'] as String?,
        activePrice: double.parse(data['active_price'].toString()),
        imageUrl: data['image_url'] as String?,
        vendorId: data['vendor_id'] as String,
        vendorName: vendorName,
        rating: data['rating'] != null
            ? double.parse(data['rating'].toString())
            : 0.0,
        reviewCount: (data['review_count'] as int?) ?? 0,
        includedItems: (data['included_items'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            [],
        excludedItems: (data['excluded_items'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            [],
        beforeAfterPairs: (data['before_after_pairs'] as List<dynamic>?)
                ?.map((e) => Map<String, String>.from((e as Map)
                    .map((k, v) => MapEntry(k.toString(), v.toString()))))
                .toList() ??
            [],
      );
    } catch (e) {
      debugPrint(
          '[CatalogService] fetchCustomServiceById($customServiceId) error: $e');
      return null;
    }
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
