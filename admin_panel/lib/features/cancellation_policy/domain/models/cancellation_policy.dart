class CancellationPolicySlab {
  final String? id;
  final String policyId;
  final int fromMinutes;
  final int? toMinutes;
  final double feeAmount;
  final String? label;
  final int sortOrder;

  const CancellationPolicySlab({
    this.id,
    required this.policyId,
    required this.fromMinutes,
    this.toMinutes,
    required this.feeAmount,
    this.label,
    this.sortOrder = 0,
  });

  factory CancellationPolicySlab.fromJson(
      Map<String, dynamic> json, String policyId) =>
      CancellationPolicySlab(
        id: json['id'] as String?,
        policyId: policyId,
        fromMinutes: (json['from_minutes'] as num?)?.toInt() ?? 0,
        toMinutes: (json['to_minutes'] as num?)?.toInt(),
        feeAmount: (json['fee_amount'] as num?)?.toDouble() ?? 0,
        label: json['label'] as String?,
        sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      );

  String get rangeLabel {
    String _fmt(int mins) {
      final h = mins / 60.0;
      return h == h.truncateToDouble() ? '${h.toInt()}h' : '${h.toStringAsFixed(1)}h';
    }
    if (toMinutes == null) return '${_fmt(fromMinutes)}+';
    return '${_fmt(fromMinutes)} – ${_fmt(toMinutes!)}';
  }
}

class CancellationPolicy {
  final String id;
  final String policyType;
  final bool isEnabled;
  final String label;
  final String? description;
  final List<CancellationPolicySlab> slabs;

  const CancellationPolicy({
    required this.id,
    required this.policyType,
    required this.isEnabled,
    required this.label,
    this.description,
    this.slabs = const [],
  });

  bool get isBeforeAssignment => policyType == 'before_assignment';

  factory CancellationPolicy.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String;
    final slabsJson = json['slabs'] as List? ?? [];
    return CancellationPolicy(
      id: id,
      policyType: json['policy_type'] as String,
      isEnabled: (json['is_enabled'] as bool?) ?? false,
      label: json['label'] as String? ?? '',
      description: json['description'] as String?,
      slabs: slabsJson
          .map((s) => CancellationPolicySlab.fromJson(s as Map<String, dynamic>, id))
          .toList(),
    );
  }
}
