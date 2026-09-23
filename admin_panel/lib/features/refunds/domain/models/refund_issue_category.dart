class RefundIssueCategory {
  final String id;
  final String key;
  final String label;
  final String? description;
  final bool requiresEvidence;
  final bool isActive;
  final int sortOrder;

  const RefundIssueCategory({
    required this.id,
    required this.key,
    required this.label,
    this.description,
    required this.requiresEvidence,
    required this.isActive,
    required this.sortOrder,
  });

  factory RefundIssueCategory.fromMap(Map<String, dynamic> m) =>
      RefundIssueCategory(
        id: m['id'] as String,
        key: m['key'] as String,
        label: m['label'] as String,
        description: m['description'] as String?,
        requiresEvidence: m['requires_evidence'] as bool? ?? true,
        isActive: m['is_active'] as bool? ?? true,
        sortOrder: m['sort_order'] as int? ?? 0,
      );
}
