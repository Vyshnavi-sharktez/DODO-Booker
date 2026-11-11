class InstaHelpFinancialConfig {
  final String id;
  final String modeId;
  final double gstPercent;
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
      surgeFeeEnabled: m['surge_fee_enabled'] as bool? ?? false,
      surgeFeeType: m['surge_fee_type'] as String? ?? 'percentage',
      surgeFeeValue: (m['surge_fee_value'] as num?)?.toDouble() ?? 0,
      serviceChargeEnabled: m['service_charge_enabled'] as bool? ?? false,
      serviceChargeType: m['service_charge_type'] as String? ?? 'fixed',
      serviceChargeValue: (m['service_charge_value'] as num?)?.toDouble() ?? 0,
    );
  }

  String get surgeFeeLabel {
    if (!surgeFeeEnabled || surgeFeeValue <= 0) return 'None';
    return surgeFeeType == 'percentage'
        ? '${surgeFeeValue.toStringAsFixed(0)}%'
        : '₹${surgeFeeValue.toStringAsFixed(0)}';
  }

  String get serviceChargeLabel {
    if (!serviceChargeEnabled || serviceChargeValue <= 0) return 'None';
    return serviceChargeType == 'percentage'
        ? '${serviceChargeValue.toStringAsFixed(0)}%'
        : '₹${serviceChargeValue.toStringAsFixed(0)}';
  }
}
