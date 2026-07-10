class TaxSettingsModel {
  final String? id;
  final bool isEnabled;
  final String taxName;
  final String taxType; // 'percentage' | 'fixed'
  final double taxValue;
  final bool applyOnServices;
  final bool applyOnAddons;
  final bool applyOnPackages;
  final bool displaySeparately;

  const TaxSettingsModel({
    this.id,
    required this.isEnabled,
    required this.taxName,
    required this.taxType,
    required this.taxValue,
    required this.applyOnServices,
    required this.applyOnAddons,
    required this.applyOnPackages,
    required this.displaySeparately,
  });

  static const TaxSettingsModel defaults = TaxSettingsModel(
    id: null,
    isEnabled: true,
    taxName: 'GST',
    taxType: 'percentage',
    taxValue: 18.0,
    applyOnServices: true,
    applyOnAddons: true,
    applyOnPackages: false,
    displaySeparately: true,
  );

  factory TaxSettingsModel.fromJson(Map<String, dynamic> json) {
    return TaxSettingsModel(
      id: json['id'] as String?,
      isEnabled: (json['is_enabled'] as bool?) ?? true,
      taxName: (json['tax_name'] as String?) ?? 'GST',
      taxType: (json['tax_type'] as String?) ?? 'percentage',
      taxValue: (json['tax_value'] as num?)?.toDouble() ?? 18.0,
      applyOnServices: (json['apply_on_services'] as bool?) ?? true,
      applyOnAddons: (json['apply_on_addons'] as bool?) ?? true,
      applyOnPackages: (json['apply_on_packages'] as bool?) ?? false,
      displaySeparately: (json['display_separately'] as bool?) ?? true,
    );
  }

  /// Computes the tax amount on a service subtotal.
  /// Returns 0 if tax is disabled or doesn't apply to services.
  double computeTax(double subtotal) {
    if (!isEnabled || !applyOnServices) return 0.0;
    if (taxType == 'fixed') return taxValue;
    return subtotal * taxValue / 100;
  }

  /// Human-readable label for the tax line in the price summary.
  String get displayLabel {
    if (taxType == 'fixed') return '$taxName (₹${taxValue.toInt()})';
    final pct = taxValue == taxValue.truncateToDouble()
        ? '${taxValue.toInt()}%'
        : '${taxValue.toStringAsFixed(1)}%';
    return '$taxName ($pct)';
  }
}
