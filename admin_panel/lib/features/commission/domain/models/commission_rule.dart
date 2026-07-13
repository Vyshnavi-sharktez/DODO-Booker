class CommissionRule {
  final String id;
  final String ruleType; // 'global' | 'category' | 'vendor'
  final String? targetId;
  final String commissionType; // 'percentage' | 'fixed'
  final double commissionValue;
  final bool isEnabled;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  const CommissionRule({
    required this.id,
    required this.ruleType,
    this.targetId,
    required this.commissionType,
    required this.commissionValue,
    required this.isEnabled,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  factory CommissionRule.fromMap(Map<String, dynamic> map) {
    return CommissionRule(
      id: map['id'] as String,
      ruleType: map['rule_type'] as String,
      targetId: map['target_id'] as String?,
      commissionType: map['commission_type'] as String? ?? 'percentage',
      commissionValue: (map['commission_value'] as num? ?? 0).toDouble(),
      isEnabled: map['is_enabled'] as bool? ?? true,
      notes: map['notes'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  /// Computes platform commission amount from gross earnings.
  double compute(double grossAmount) {
    if (!isEnabled || grossAmount <= 0) return 0.0;
    if (commissionType == 'percentage') {
      return grossAmount * commissionValue / 100;
    }
    return commissionValue;
  }

  String get displayLabel {
    if (!isEnabled) return 'Disabled';
    if (commissionType == 'percentage') {
      return '${commissionValue.toStringAsFixed(commissionValue.truncateToDouble() == commissionValue ? 0 : 2)}%';
    }
    return '₹${commissionValue.toStringAsFixed(2)}';
  }

  CommissionRule copyWith({
    String? id,
    String? ruleType,
    String? targetId,
    String? commissionType,
    double? commissionValue,
    bool? isEnabled,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CommissionRule(
      id: id ?? this.id,
      ruleType: ruleType ?? this.ruleType,
      targetId: targetId ?? this.targetId,
      commissionType: commissionType ?? this.commissionType,
      commissionValue: commissionValue ?? this.commissionValue,
      isEnabled: isEnabled ?? this.isEnabled,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
