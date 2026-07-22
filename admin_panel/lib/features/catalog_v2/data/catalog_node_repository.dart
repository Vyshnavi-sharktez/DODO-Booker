import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/models/catalog_node.dart';

class CatalogNodeRepository {
  final SupabaseClient _supabase;

  const CatalogNodeRepository(this._supabase);

  /// Fetches ALL nodes (active and inactive) from the view.
  Future<List<CatalogNode>> fetchAll() async {
    final data = await _supabase
        .from('catalog_nodes_view')
        .select()
        .order('sort_order', ascending: true)
        .order('name', ascending: true);
    return (data as List<dynamic>)
        .map((r) => CatalogNode.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  /// Creates a new catalog item.  If [parentId] is provided, a parent-child
  /// relationship is also created so the item appears under that category.
  Future<CatalogNode> createNode({
    String? parentId,
    required String name,
    required String slug,
    String? description,
    String? imageUrl,
    String? iconKey,
    required int sortOrder,
    required bool isActive,
    required bool isBookable,
    double? basePrice,
    int? estimatedDuration,
    double? minimumOrderAmount,
  }) async {
    final data = await _supabase
        .from('catalog_nodes')
        .insert({
          'name': name,
          'slug': slug,
          if (description != null && description.isNotEmpty)
            'description': description,
          if (imageUrl != null && imageUrl.isNotEmpty) 'image_url': imageUrl,
          if (iconKey != null && iconKey.isNotEmpty) 'icon_key': iconKey,
          'sort_order': sortOrder,
          'is_active': isActive,
          'is_bookable': isBookable,
          if (basePrice != null) 'base_price': basePrice,
          if (estimatedDuration != null)
            'estimated_duration': estimatedDuration,
          if (minimumOrderAmount != null)
            'minimum_order_amount': minimumOrderAmount,
        })
        .select()
        .single();

    final nodeId = data['id'] as String;

    if (parentId != null) {
      await _supabase.from('catalog_node_relationships').insert({
        'parent_id': parentId,
        'child_id': nodeId,
        'sort_order': sortOrder,
      });
    }

    return _fetchById(nodeId);
  }

  /// Updates node properties only.
  /// Parent-category relationships are managed separately via
  /// [addParent] and [removeParent].
  Future<CatalogNode> updateNode(
    String id, {
    required String name,
    required String slug,
    String? description,
    String? imageUrl,
    String? iconKey,
    required int sortOrder,
    required bool isActive,
    required bool isBookable,
    double? basePrice,
    int? estimatedDuration,
    double? minimumOrderAmount,
  }) async {
    await _supabase
        .from('catalog_nodes')
        .update({
          'name': name,
          'slug': slug,
          'description':
              description?.isNotEmpty == true ? description : null,
          'image_url': imageUrl?.isNotEmpty == true ? imageUrl : null,
          'icon_key': iconKey?.isNotEmpty == true ? iconKey : null,
          'sort_order': sortOrder,
          'is_active': isActive,
          'is_bookable': isBookable,
          'base_price': basePrice,
          'estimated_duration': estimatedDuration,
          'minimum_order_amount': minimumOrderAmount,
        })
        .eq('id', id);
    return _fetchById(id);
  }

  /// Permanently deletes a catalog item and all its removable dependencies.
  ///
  /// Historical booking records are preserved intact — booking_items.service_id
  /// has no FK constraint to catalog_nodes, so those rows are unaffected.
  ///
  /// Deletion order:
  ///   1. wishlists.node_id           — customer data, deleted.
  ///   2. service_attribute_options   — child of service_attributes, deleted first.
  ///   3. service_attributes.node_id  — service config, deleted.
  ///   4. service_scheduling.service_id — scheduling config, deleted.
  ///   5. catalog_nodes               — deleted; DB CASCADE removes relationship rows.
  Future<void> deleteNode(String id) async {
    // 1. Wishlists: customer data — remove referencing rows.
    await _supabase.from('wishlists').delete().eq('node_id', id);

    // 2-3. Service attributes: delete options (child FK) then attributes.
    final attrs = await _supabase
        .from('service_attributes')
        .select('id')
        .eq('node_id', id);
    final attrIds = (attrs as List<dynamic>)
        .map((a) => (a as Map<String, dynamic>)['id'] as String)
        .toList();
    if (attrIds.isNotEmpty) {
      await _supabase
          .from('service_attribute_options')
          .delete()
          .inFilter('attribute_id', attrIds);
    }
    await _supabase.from('service_attributes').delete().eq('node_id', id);

    // 4. Scheduling config — no FK constraint but clean up the config row.
    await _supabase.from('service_scheduling').delete().eq('service_id', id);

    // 5. Delete the node; catalog_node_relationships rows cascade automatically.
    await _supabase.from('catalog_nodes').delete().eq('id', id);
  }

  Future<void> toggleActive(String id, {required bool isActive}) async {
    await _supabase
        .from('catalog_nodes')
        .update({'is_active': isActive})
        .eq('id', id);
  }

  /// Sets availability on the relationship edge (parent → child).
  /// Use for non-root nodes so the change is path-scoped.
  Future<void> setRelationshipAvailability(
    String parentId,
    String childId,
    String status,
    String? message,
  ) async {
    await _supabase
        .from('catalog_node_relationships')
        .update({
          'availability_status': status,
          'unavailability_message': message,
        })
        .eq('parent_id', parentId)
        .eq('child_id', childId);
  }

  /// Sets availability on the node itself.
  /// Use for root nodes (no parent) or global node-wide overrides.
  Future<void> setNodeAvailability(
    String nodeId,
    String status,
    String? message,
  ) async {
    await _supabase
        .from('catalog_nodes')
        .update({
          'availability_status': status,
          'unavailability_message': message,
        })
        .eq('id', nodeId);
  }

  /// Fetches ALL relationship availability statuses in one query.
  /// Returns a map keyed by "$parentId|$childId" → availability_status.
  /// Used by the admin tree to show the correct per-path icon without N+1 queries.
  Future<Map<String, String>> fetchAllRelationshipStatuses() async {
    final data = await _supabase
        .from('catalog_node_relationships')
        .select('parent_id, child_id, availability_status');
    return {
      for (final row in data as List<dynamic>)
        '${(row as Map<String, dynamic>)['parent_id']}|${row['child_id']}':
            (row['availability_status'] as String?) ?? 'active',
    };
  }

  /// Returns the current availability state for a specific relationship edge.
  Future<({String status, String? message})> fetchRelationshipAvailability(
    String parentId,
    String childId,
  ) async {
    final row = await _supabase
        .from('catalog_node_relationships')
        .select('availability_status, unavailability_message')
        .eq('parent_id', parentId)
        .eq('child_id', childId)
        .single();
    return (
      status: (row['availability_status'] as String?) ?? 'active',
      message: row['unavailability_message'] as String?,
    );
  }

  Future<void> toggleBookable(String id, {required bool isBookable}) async {
    await _supabase
        .from('catalog_nodes')
        .update({'is_bookable': isBookable})
        .eq('id', id);
  }

  // ── Location restrictions ─────────────────────────────────────────────────────

  /// Returns the area IDs currently blocked for [nodeId] in the given scope.
  /// When [parentId] is set, returns the relationship-scoped restrictions for
  /// the (parentId → nodeId) edge. When null, returns node-scoped restrictions.
  Future<List<String>> fetchLocationRestrictions(
      String nodeId, String? parentId) async {
    if (parentId != null) {
      final relRow = await _supabase
          .from('catalog_node_relationships')
          .select('id')
          .eq('parent_id', parentId)
          .eq('child_id', nodeId)
          .single();
      final relId = relRow['id'] as String;
      final rows = await _supabase
          .from('catalog_node_location_restrictions')
          .select('area_id')
          .eq('node_id', nodeId)
          .eq('relationship_id', relId);
      return (rows as List<dynamic>)
          .map((r) => (r as Map<String, dynamic>)['area_id'] as String)
          .toList();
    } else {
      final rows = await _supabase
          .from('catalog_node_location_restrictions')
          .select('area_id')
          .eq('node_id', nodeId)
          .isFilter('relationship_id', null);
      return (rows as List<dynamic>)
          .map((r) => (r as Map<String, dynamic>)['area_id'] as String)
          .toList();
    }
  }

  /// Replaces location restrictions for [nodeId] in the given scope.
  /// Deletes existing rows then inserts the new [areaIds].
  /// An empty [areaIds] list clears all restrictions for the scope.
  Future<void> saveLocationRestrictions(
      String nodeId, String? parentId, List<String> areaIds) async {
    String? relId;
    if (parentId != null) {
      final relRow = await _supabase
          .from('catalog_node_relationships')
          .select('id')
          .eq('parent_id', parentId)
          .eq('child_id', nodeId)
          .single();
      relId = relRow['id'] as String;
      await _supabase
          .from('catalog_node_location_restrictions')
          .delete()
          .eq('node_id', nodeId)
          .eq('relationship_id', relId);
    } else {
      await _supabase
          .from('catalog_node_location_restrictions')
          .delete()
          .eq('node_id', nodeId)
          .isFilter('relationship_id', null);
    }
    if (areaIds.isNotEmpty) {
      await _supabase.from('catalog_node_location_restrictions').insert(
            areaIds
                .map((aId) => {
                      'node_id': nodeId,
                      if (relId != null) 'relationship_id': relId,
                      'area_id': aId,
                    })
                .toList(),
          );
    }
  }

  /// Returns a set of lookup keys indicating which nodes/paths have at least
  /// one location restriction row.
  ///
  ///   "node:<nodeId>"            — node-scoped restriction (relationship_id IS NULL)
  ///   "rel:<parentId>|<nodeId>"  — path-scoped restriction for a specific edge
  ///
  /// Used by the admin tree to show the location-restricted icon without
  /// opening the dialog. Deduplicated via Set (multiple areas per path produce
  /// only one key).
  Future<Set<String>> fetchAllLocationRestrictionKeys() async {
    final rows = await _supabase
        .from('catalog_node_location_restrictions')
        .select('node_id, relationship_id, catalog_node_relationships(parent_id)');
    final keys = <String>{};
    for (final r in rows as List<dynamic>) {
      final row = r as Map<String, dynamic>;
      final nodeId = row['node_id'] as String;
      final relId = row['relationship_id'] as String?;
      if (relId == null) {
        keys.add('node:$nodeId');
      } else {
        final rel = row['catalog_node_relationships'] as Map<String, dynamic>?;
        final parentId = rel?['parent_id'] as String?;
        if (parentId != null) {
          keys.add('rel:$parentId|$nodeId');
        }
      }
    }
    return keys;
  }

  // ── Category relationship management ─────────────────────────────────────────

  /// Lists [nodeId] under [parentId] as a new parent category.
  /// The DB rejects the relationship if it would create a loop
  /// or if the pair already exists (UNIQUE constraint).
  Future<void> addParent(String nodeId, String parentId,
      {int sortOrder = 0}) async {
    await _supabase.from('catalog_node_relationships').insert({
      'parent_id': parentId,
      'child_id': nodeId,
      'sort_order': sortOrder,
    });
  }

  /// Removes the listing of [nodeId] from under [parentId].
  /// If this was the item's only category, it becomes a top-level item.
  Future<void> removeParent(String nodeId, String parentId) async {
    await _supabase
        .from('catalog_node_relationships')
        .delete()
        .eq('parent_id', parentId)
        .eq('child_id', nodeId);
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  /// Returns the count of direct children listed under [id].
  /// Used to warn the admin before deleting a category.
  Future<int> countChildren(String id) async {
    final data = await _supabase
        .from('catalog_node_relationships')
        .select('id')
        .eq('parent_id', id);
    return (data as List).length;
  }

  Future<CatalogNode> _fetchById(String id) async {
    final data = await _supabase
        .from('catalog_nodes_view')
        .select()
        .eq('id', id)
        .single();
    return CatalogNode.fromMap(data);
  }
}
