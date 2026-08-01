class AmcPlan {
  final String id;
  final String planName;
  final String packageDuration;
  final int? packageDurationValue; // days, only for 'custom'
  final String serviceInterval;
  final int? serviceIntervalValue; // days, only for 'custom'
  final double pricePerVisit;
  final String discountType; // 'percentage' | 'fixed'
  final double discountValue;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const AmcPlan({
    required this.id,
    required this.planName,
    required this.packageDuration,
    this.packageDurationValue,
    required this.serviceInterval,
    this.serviceIntervalValue,
    required this.pricePerVisit,
    required this.discountType,
    required this.discountValue,
    required this.isActive,
    this.createdAt,
    this.updatedAt,
  });

  // ── Calculated fields ──────────────────────────────────────────────────────

  int get packageDays => switch (packageDuration) {
        'monthly' => 30,
        'quarterly' => 91,
        'half_yearly' => 182,
        'yearly' => 365,
        _ => packageDurationValue ?? 30,
      };

  int get intervalDays => switch (serviceInterval) {
        'weekly' => 7,
        'bi_weekly' => 14,
        'monthly' => 30,
        _ => serviceIntervalValue ?? 30,
      };

  int get numVisits =>
      intervalDays > 0 ? (packageDays / intervalDays).floor().clamp(1, 9999) : 1;

  double get originalTotal => pricePerVisit * numVisits;

  double get discountAmount => discountType == 'percentage'
      ? originalTotal * discountValue / 100
      : discountValue;

  double get finalPrice =>
      (originalTotal - discountAmount).clamp(0.0, double.infinity);

  // ── Display helpers ────────────────────────────────────────────────────────

  String get packageDurationLabel => switch (packageDuration) {
        'monthly' => 'Monthly',
        'quarterly' => 'Quarterly',
        'half_yearly' => 'Half-Yearly',
        'yearly' => 'Yearly',
        _ => 'Custom (${packageDurationValue ?? 0} days)',
      };

  String get serviceIntervalLabel => switch (serviceInterval) {
        'weekly' => 'Weekly',
        'bi_weekly' => 'Bi-Weekly',
        'monthly' => 'Monthly',
        _ => 'Every ${serviceIntervalValue ?? 0} days',
      };

  // ── Serialisation ──────────────────────────────────────────────────────────

  factory AmcPlan.fromMap(Map<String, dynamic> map) => AmcPlan(
        id: map['id'] as String,
        planName: map['plan_name'] as String? ?? '',
        packageDuration: map['package_duration'] as String? ?? 'yearly',
        packageDurationValue: map['package_duration_value'] as int?,
        serviceInterval: map['service_interval'] as String? ?? 'monthly',
        serviceIntervalValue: map['service_interval_value'] as int?,
        pricePerVisit: (map['price_per_visit'] as num?)?.toDouble() ?? 0.0,
        discountType: map['discount_type'] as String? ?? 'percentage',
        discountValue: (map['discount_value'] as num?)?.toDouble() ?? 0.0,
        isActive: map['is_active'] as bool? ?? true,
        createdAt: map['created_at'] != null
            ? DateTime.tryParse(map['created_at'] as String)
            : null,
        updatedAt: map['updated_at'] != null
            ? DateTime.tryParse(map['updated_at'] as String)
            : null,
      );

  AmcPlan copyWith({
    String? planName,
    String? packageDuration,
    int? packageDurationValue,
    String? serviceInterval,
    int? serviceIntervalValue,
    double? pricePerVisit,
    String? discountType,
    double? discountValue,
    bool? isActive,
  }) =>
      AmcPlan(
        id: id,
        planName: planName ?? this.planName,
        packageDuration: packageDuration ?? this.packageDuration,
        packageDurationValue: packageDurationValue ?? this.packageDurationValue,
        serviceInterval: serviceInterval ?? this.serviceInterval,
        serviceIntervalValue: serviceIntervalValue ?? this.serviceIntervalValue,
        pricePerVisit: pricePerVisit ?? this.pricePerVisit,
        discountType: discountType ?? this.discountType,
        discountValue: discountValue ?? this.discountValue,
        isActive: isActive ?? this.isActive,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
}
