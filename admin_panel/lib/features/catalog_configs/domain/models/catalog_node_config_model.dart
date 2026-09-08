class CatalogNodeConfigModel {
  final String id;
  final String module;
  final String? relationshipId;
  final String? nodeId;
  final String? customServiceId;
  final Map<String, dynamic> config;
  final bool isEnabled;
  final String? notes;

  const CatalogNodeConfigModel({
    required this.id,
    required this.module,
    this.relationshipId,
    this.nodeId,
    this.customServiceId,
    required this.config,
    required this.isEnabled,
    this.notes,
  });

  bool get isRelationshipScoped => relationshipId != null;

  factory CatalogNodeConfigModel.fromMap(Map<String, dynamic> map) {
    return CatalogNodeConfigModel(
      id: map['id'] as String,
      module: map['module'] as String,
      relationshipId: map['relationship_id'] as String?,
      nodeId: map['node_id'] as String?,
      customServiceId: map['custom_service_id'] as String?,
      config: (map['config'] as Map<dynamic, dynamic>?)
              ?.cast<String, dynamic>() ??
          {},
      isEnabled: (map['is_enabled'] as bool?) ?? true,
      notes: map['notes'] as String?,
    );
  }

  Map<String, dynamic> toInsertMap() {
    return {
      'module': module,
      if (relationshipId != null) 'relationship_id': relationshipId,
      if (nodeId != null) 'node_id': nodeId,
      if (customServiceId != null) 'custom_service_id': customServiceId,
      'config': config,
      'is_enabled': isEnabled,
      if (notes != null) 'notes': notes,
    };
  }
}
