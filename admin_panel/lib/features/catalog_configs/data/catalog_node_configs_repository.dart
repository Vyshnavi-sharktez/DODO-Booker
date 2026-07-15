import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/models/catalog_node_config_model.dart';

class CatalogNodeConfigsRepository {
  CatalogNodeConfigsRepository(this._client);
  final SupabaseClient _client;

  /// Looks up the relationship_id for (parentNodeId, childNodeId).
  /// Returns null when no such relationship exists.
  Future<String?> fetchRelationshipId(
    String parentNodeId,
    String childNodeId,
  ) async {
    final row = await _client
        .from('catalog_node_relationships')
        .select('id')
        .eq('parent_id', parentNodeId)
        .eq('child_id', childNodeId)
        .maybeSingle();
    return row?['id'] as String?;
  }

  /// Fetches all configs for a given relationship_id across all modules.
  Future<List<CatalogNodeConfigModel>> fetchForRelationship(
    String relationshipId,
  ) async {
    final rows = await _client
        .from('catalog_node_configs')
        .select()
        .eq('relationship_id', relationshipId);
    return rows
        .map((r) => CatalogNodeConfigModel.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  /// Fetches all node-scoped configs for a given node_id across all modules.
  Future<List<CatalogNodeConfigModel>> fetchForNode(String nodeId) async {
    final rows = await _client
        .from('catalog_node_configs')
        .select()
        .eq('node_id', nodeId)
        .isFilter('relationship_id', null);
    return rows
        .map((r) => CatalogNodeConfigModel.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  /// Upserts a config row using explicit SELECT → UPDATE-or-INSERT.
  /// PostgREST cannot target partial unique indexes (those with WHERE clauses)
  /// via onConflict, so we handle the conflict check in Dart instead.
  Future<void> upsert(CatalogNodeConfigModel cfg) async {
    final Map<String, dynamic>? existing;

    if (cfg.isRelationshipScoped) {
      existing = await _client
          .from('catalog_node_configs')
          .select('id')
          .eq('module', cfg.module)
          .eq('relationship_id', cfg.relationshipId!)
          .maybeSingle();
    } else {
      existing = await _client
          .from('catalog_node_configs')
          .select('id')
          .eq('module', cfg.module)
          .eq('node_id', cfg.nodeId!)
          .isFilter('relationship_id', null)
          .maybeSingle();
    }

    final updatePayload = <String, dynamic>{
      'config': cfg.config,
      'is_enabled': cfg.isEnabled,
      'notes': cfg.notes,
    };

    if (existing != null) {
      await _client
          .from('catalog_node_configs')
          .update(updatePayload)
          .eq('id', existing['id'] as String);
    } else {
      await _client
          .from('catalog_node_configs')
          .insert(cfg.toInsertMap());
    }
  }

  Future<void> deleteById(String id) async {
    await _client.from('catalog_node_configs').delete().eq('id', id);
  }

  Future<void> setEnabled(String id, {required bool enabled}) async {
    await _client
        .from('catalog_node_configs')
        .update({'is_enabled': enabled})
        .eq('id', id);
  }

  /// Calls resolve_catalog_module_config and returns the effective JSONB config,
  /// or null when no scoped config exists for the given path.
  Future<Map<String, dynamic>?> resolveConfig(
    String module,
    String nodeId,
    String? parentId,
  ) async {
    final result = await _client.rpc(
      'resolve_catalog_module_config',
      params: {
        'p_module': module,
        'p_service_id': nodeId,
        'p_parent_id': parentId,
      },
    );
    if (result == null) return null;
    return Map<String, dynamic>.from(result as Map);
  }
}
