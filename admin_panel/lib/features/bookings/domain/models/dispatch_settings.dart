class DispatchSettings {
  final String id;
  final bool isTierDispatchEnabled;
  final int tierTimeoutSeconds;
  final int maxAttemptsPerTier;
  final DateTime? updatedAt;
  final String? updatedBy;

  const DispatchSettings({
    required this.id,
    required this.isTierDispatchEnabled,
    required this.tierTimeoutSeconds,
    required this.maxAttemptsPerTier,
    this.updatedAt,
    this.updatedBy,
  });

  factory DispatchSettings.fromMap(Map<String, dynamic> map) {
    return DispatchSettings(
      id: map['id'] as String? ?? '',
      isTierDispatchEnabled: map['is_tier_dispatch_enabled'] as bool? ?? true,
      tierTimeoutSeconds: map['tier_timeout_seconds'] as int? ?? 60,
      maxAttemptsPerTier: map['max_attempts_per_tier'] as int? ?? 1,
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'] as String)
          : null,
      updatedBy: map['updated_by'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'is_tier_dispatch_enabled': isTierDispatchEnabled,
      'tier_timeout_seconds': tierTimeoutSeconds,
      'max_attempts_per_tier': maxAttemptsPerTier,
      if (updatedBy != null) 'updated_by': updatedBy,
    };
  }

  DispatchSettings copyWith({
    String? id,
    bool? isTierDispatchEnabled,
    int? tierTimeoutSeconds,
    int? maxAttemptsPerTier,
    DateTime? updatedAt,
    String? updatedBy,
  }) {
    return DispatchSettings(
      id: id ?? this.id,
      isTierDispatchEnabled:
          isTierDispatchEnabled ?? this.isTierDispatchEnabled,
      tierTimeoutSeconds: tierTimeoutSeconds ?? this.tierTimeoutSeconds,
      maxAttemptsPerTier: maxAttemptsPerTier ?? this.maxAttemptsPerTier,
      updatedAt: updatedAt ?? this.updatedAt,
      updatedBy: updatedBy ?? this.updatedBy,
    );
  }
}
