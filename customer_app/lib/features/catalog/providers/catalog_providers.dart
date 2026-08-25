import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../models/faq_model.dart';
import '../models/catalog_node_model.dart';
import '../services/catalog_service.dart';

final catalogServiceProvider =
    Provider<CatalogService>((ref) => CatalogService());

/// All active top-level catalog items (no parent category).
final rootCatalogNodesProvider =
    FutureProvider<List<CatalogNodeModel>>((ref) {
  return ref.read(catalogServiceProvider).fetchRootNodes();
});

/// A single catalog node by ID (used for deep-link recovery).
final catalogNodeProvider =
    FutureProvider.family<CatalogNodeModel?, String>((ref, id) {
  return ref.read(catalogServiceProvider).fetchNode(id);
});

/// Active direct children of a catalog node.
final catalogNodeChildrenProvider =
    FutureProvider.family<List<CatalogNodeModel>, String>((ref, parentId) {
  return ref.read(catalogServiceProvider).fetchChildren(parentId);
});

/// FAQs for a catalog node scoped to a parent context.
/// Static service_faqs are global to the node; answered customer_questions are
/// scoped to (nodeId, parentNodeId) so a shared sub-service shows distinct Q&A
/// sets under each parent.
typedef _FaqsKey = ({String nodeId, String? parentNodeId});

final catalogNodeFaqsProvider =
    FutureProvider.family<List<FaqModel>, _FaqsKey>((ref, key) async {
  final service = ref.read(catalogServiceProvider);
  final results = await Future.wait([
    service.fetchFaqsForNode(key.nodeId),
    service.fetchAnsweredQuestionsForNode(key.nodeId, key.parentNodeId),
  ]);
  return [...results[0], ...results[1]];
});

/// Effective availability of a node for a given parent context.
/// Pass parentId = node.parentId as fallback when the true path is unknown
/// (deep-link entry) so the canonical path is used instead.
/// Provide lat/lng from the customer's default address to also enforce
/// location restrictions; omit to skip the location check.
typedef _AvailabilityParams = ({
  String nodeId,
  String? parentId,
  double? lat,
  double? lng,
});

final nodeAvailabilityProvider = FutureProvider.family<
    ({String status, String? message}), _AvailabilityParams>(
  (ref, params) => ref.read(catalogServiceProvider).checkAvailability(
        params.nodeId,
        params.parentId,
        lat: params.lat,
        lng: params.lng,
      ),
);

/// Admin-curated before/after showcase images for a service.
/// Only images explicitly selected by Admin appear here.
/// Two-step query: avoids PostgREST FK-join caching issues for the anon role.
final serviceShowcaseImagesProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, serviceId) async {
  final client = Supabase.instance.client;

  // Step 1: ordered booking_image_ids for this catalog node.
  final showcaseRows = await client
      .from('service_showcase_images')
      .select('booking_image_id, sort_order')
      .eq('catalog_node_id', serviceId)
      .order('sort_order');

  debugPrint('[Showcase] serviceId=$serviceId  rows=${showcaseRows.length}');
  if (showcaseRows.isEmpty) return [];

  final orderedIds =
      showcaseRows.map((r) => r['booking_image_id'] as String).toList();

  // Step 2: fetch image data from booking_images (avoids PostgREST FK-join for anon).
  final imageRows = await client
      .from('booking_images')
      .select('id, image_url, image_type')
      .inFilter('id', orderedIds);

  debugPrint('[Showcase] booking_images fetched=${imageRows.length}');

  final byId = <String, Map<String, dynamic>>{
    for (final r in imageRows) r['id'] as String: r,
  };

  return orderedIds.map((id) {
    final img = byId[id];
    if (img == null) {
      debugPrint('[Showcase] WARNING: booking_image_id=$id not in booking_images');
      return null;
    }
    return <String, dynamic>{
      'image_url': img['image_url'] as String,
      'image_type': img['image_type'] as String,
    };
  }).whereType<Map<String, dynamic>>().toList();
});
