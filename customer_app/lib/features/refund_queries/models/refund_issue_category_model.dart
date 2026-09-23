class RefundIssueCategoryModel {
  final String id;
  final String key;
  final String label;
  final String? description;
  final bool requiresEvidence;
  final int sortOrder;

  const RefundIssueCategoryModel({
    required this.id,
    required this.key,
    required this.label,
    this.description,
    required this.requiresEvidence,
    required this.sortOrder,
  });

  factory RefundIssueCategoryModel.fromMap(Map<String, dynamic> map) {
    return RefundIssueCategoryModel(
      id: map['id'] as String,
      key: map['key'] as String,
      label: map['label'] as String,
      description: map['description'] as String?,
      requiresEvidence: map['requires_evidence'] as bool? ?? false,
      sortOrder: (map['sort_order'] as num?)?.toInt() ?? 0,
    );
  }
}
