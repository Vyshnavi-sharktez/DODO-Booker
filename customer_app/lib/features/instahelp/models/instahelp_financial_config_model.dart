class InstaHelpFinancialConfigModel {
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
  final Map<String, double> vendorPrices;

  const InstaHelpFinancialConfigModel({
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
    this.vendorPrices = const {},
  });

  factory InstaHelpFinancialConfigModel.fromMap(Map<String, dynamic> m) {
    final raw = m['vendor_prices'];
    final vendorPrices = <String, double>{};
    if (raw is Map) {
      raw.forEach((k, v) => vendorPrices[k as String] = (v as num).toDouble());
    }
    return InstaHelpFinancialConfigModel(
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
      vendorPrices: vendorPrices,
    );
  }

  static InstaHelpFinancialConfigModel zero(String modeId) =>
      InstaHelpFinancialConfigModel(
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

  // Returns the configured price for a specific vendor, or the duration default.
  double priceForVendor(String? vendorId, double defaultPrice) {
    if (vendorId == null) return defaultPrice;
    final custom = vendorPrices[vendorId];
    return (custom != null && custom > 0) ? custom : defaultPrice;
  }

  // ── Calculation helpers ───────────────────────────────────────────────────
  // Calc order: base → +surge → +serviceCharge → +gst = total

  double surgeAmount(double basePrice) {
    if (!surgeFeeEnabled || surgeFeeValue <= 0) return 0;
    return surgeFeeType == 'percentage'
        ? basePrice * surgeFeeValue / 100
        : surgeFeeValue;
  }

  double serviceChargeAmount(double basePrice) {
    if (!serviceChargeEnabled || serviceChargeValue <= 0) return 0;
    final subtotal = basePrice + surgeAmount(basePrice);
    return serviceChargeType == 'percentage'
        ? subtotal * serviceChargeValue / 100
        : serviceChargeValue;
  }

  double gstAmount(double basePrice) {
    if (gstPercent <= 0) return 0;
    final subtotal = basePrice + surgeAmount(basePrice) + serviceChargeAmount(basePrice);
    return subtotal * gstPercent / 100;
  }

  double totalAmount(double basePrice) {
    return basePrice +
        surgeAmount(basePrice) +
        serviceChargeAmount(basePrice) +
        gstAmount(basePrice);
  }
}
