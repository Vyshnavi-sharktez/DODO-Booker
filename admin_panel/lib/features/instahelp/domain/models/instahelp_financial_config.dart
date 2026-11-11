class InstaHelpFinancialConfig {
  final String id;
  final String modeId;
  final double gstPercent;
  final double platformCommissionPercent;
  final bool surgeFeeEnabled;
  final String surgeFeeType;
  final double surgeFeeValue;
  final bool serviceChargeEnabled;
  final String serviceChargeType;
  final double serviceChargeValue;
  const InstaHelpFinancialConfig({
    required this.id,
    required this.modeId,
    required this.gstPercent,
    required this.platformCommissionPercent,
    required this.surgeFeeEnabled,
    required this.surgeFeeType,
    required this.surgeFeeValue,
    required this.serviceChargeEnabled,
    required this.serviceChargeType,
    required this.serviceChargeValue,
  });

  factory InstaHelpFinancialConfig.fromMap(Map<String, dynamic> m) {
    return InstaHelpFinancialConfig(
      id: m['id'] as String,
      modeId: m['mode_id'] as String,
      gstPercent: (m['gst_percent'] as num?)?.toDouble() ?? 0,
      platformCommissionPercent:
          (m['platform_commission_percent'] as num?)?.toDouble() ?? 0,
      surgeFeeEnabled: m['surge_fee_enabled'] as bool? ?? false,
      surgeFeeType: m['surge_fee_type'] as String? ?? 'percentage',
      surgeFeeValue: (m['surge_fee_value'] as num?)?.toDouble() ?? 0,
      serviceChargeEnabled: m['service_charge_enabled'] as bool? ?? false,
      serviceChargeType: m['service_charge_type'] as String? ?? 'fixed',
      serviceChargeValue: (m['service_charge_value'] as num?)?.toDouble() ?? 0,
    );
  }

  static InstaHelpFinancialConfig defaultFor(String modeId) =>
      InstaHelpFinancialConfig(
        id: '',
        modeId: modeId,
        gstPercent: 0,
        platformCommissionPercent: 0,
        surgeFeeEnabled: false,
        surgeFeeType: 'percentage',
        surgeFeeValue: 0,
        serviceChargeEnabled: false,
        serviceChargeType: 'fixed',
        serviceChargeValue: 0,
      );

  InstaHelpFinancialConfig copyWith({
    double? gstPercent,
    double? platformCommissionPercent,
    bool? surgeFeeEnabled,
    String? surgeFeeType,
    double? surgeFeeValue,
    bool? serviceChargeEnabled,
    String? serviceChargeType,
    double? serviceChargeValue,
  }) =>
      InstaHelpFinancialConfig(
        id: id,
        modeId: modeId,
        gstPercent: gstPercent ?? this.gstPercent,
        platformCommissionPercent:
            platformCommissionPercent ?? this.platformCommissionPercent,
        surgeFeeEnabled: surgeFeeEnabled ?? this.surgeFeeEnabled,
        surgeFeeType: surgeFeeType ?? this.surgeFeeType,
        surgeFeeValue: surgeFeeValue ?? this.surgeFeeValue,
        serviceChargeEnabled: serviceChargeEnabled ?? this.serviceChargeEnabled,
        serviceChargeType: serviceChargeType ?? this.serviceChargeType,
        serviceChargeValue: serviceChargeValue ?? this.serviceChargeValue,
      );
}
