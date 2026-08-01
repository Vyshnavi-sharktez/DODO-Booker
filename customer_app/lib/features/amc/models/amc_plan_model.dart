class AmcPlanModel {
  final String id;
  final String planName;
  final String packageDuration;
  final int? packageDurationValue;
  final String serviceInterval;
  final int? serviceIntervalValue;
  final double pricePerVisit;
  final String discountType;
  final double discountValue;
  final bool isActive;

  const AmcPlanModel({
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
  });

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

  String get packageDurationLabel => switch (packageDuration) {
    'monthly' => 'Monthly',
    'quarterly' => 'Quarterly',
    'half_yearly' => 'Half-Yearly',
    'yearly' => 'Yearly',
    _ => '${packageDurationValue ?? 0} days',
  };

  String get serviceIntervalLabel => switch (serviceInterval) {
    'weekly' => 'Weekly',
    'bi_weekly' => 'Bi-Weekly',
    'monthly' => 'Monthly',
    _ => 'Every ${serviceIntervalValue ?? 0} days',
  };

  // Backward-compatibility getters used by booking flow files.
  String get name => planName;
  String get recurrenceInterval => serviceIntervalLabel;

  factory AmcPlanModel.fromMap(Map<String, dynamic> m) => AmcPlanModel(
        id: m['id'] as String? ?? '',
        planName: m['plan_name'] as String? ?? '',
        packageDuration: m['package_duration'] as String? ?? 'yearly',
        packageDurationValue: m['package_duration_value'] as int?,
        serviceInterval: m['service_interval'] as String? ?? 'monthly',
        serviceIntervalValue: m['service_interval_value'] as int?,
        pricePerVisit: (m['price_per_visit'] as num?)?.toDouble() ?? 0.0,
        discountType: m['discount_type'] as String? ?? 'percentage',
        discountValue: (m['discount_value'] as num?)?.toDouble() ?? 0.0,
        isActive: m['is_active'] as bool? ?? true,
      );
}
