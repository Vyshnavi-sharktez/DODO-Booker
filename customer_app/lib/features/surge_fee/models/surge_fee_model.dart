class SurgeFeeModel {
  final String? id;
  final bool isEnabled;
  final String surgeName;
  final String surgeType; // 'percentage' | 'fixed'
  final double surgeValue;
  final String? description;

  const SurgeFeeModel({
    this.id,
    required this.isEnabled,
    required this.surgeName,
    required this.surgeType,
    required this.surgeValue,
    this.description,
  });

  static const SurgeFeeModel defaults = SurgeFeeModel(
    id: null,
    isEnabled: false,
    surgeName: 'Surge Fee',
    surgeType: 'percentage',
    surgeValue: 0.0,
    description: null,
  );

  factory SurgeFeeModel.fromJson(Map<String, dynamic> json) {
    return SurgeFeeModel(
      id: json['id'] as String?,
      isEnabled: (json['is_enabled'] as bool?) ?? false,
      surgeName: (json['surge_name'] as String?) ?? 'Surge Fee',
      surgeType: (json['surge_type'] as String?) ?? 'percentage',
      surgeValue: (json['surge_value'] as num?)?.toDouble() ?? 0.0,
      description: json['description'] as String?,
    );
  }

  /// Computes the surge amount on a service subtotal (applied before GST).
  double computeSurge(double subtotal) {
    if (!isEnabled) return 0.0;
    if (surgeType == 'fixed') return surgeValue;
    return subtotal * surgeValue / 100;
  }

  /// Human-readable label for the surge line in the price summary.
  String get displayLabel {
    if (surgeType == 'fixed') return '$surgeName (₹${surgeValue.toInt()})';
    final pct = surgeValue == surgeValue.truncateToDouble()
        ? '${surgeValue.toInt()}%'
        : '${surgeValue.toStringAsFixed(1)}%';
    return '$surgeName ($pct)';
  }
}
