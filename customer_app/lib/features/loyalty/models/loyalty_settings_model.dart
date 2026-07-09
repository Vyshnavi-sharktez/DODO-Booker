class LoyaltySettingsModel {
  final bool isEnabled;
  final bool earnEnabled;
  final bool redeemEnabled;
  final int earnPer100;
  final int minRedeemPoints;
  final double maxRedeemPercentage;

  const LoyaltySettingsModel({
    required this.isEnabled,
    required this.earnEnabled,
    required this.redeemEnabled,
    required this.earnPer100,
    required this.minRedeemPoints,
    required this.maxRedeemPercentage,
  });

  factory LoyaltySettingsModel.fromJson(Map<String, dynamic> json) {
    return LoyaltySettingsModel(
      isEnabled: json['is_enabled'] as bool? ?? true,
      earnEnabled: json['earn_enabled'] as bool? ?? true,
      redeemEnabled: json['redeem_enabled'] as bool? ?? true,
      earnPer100: json['earn_per_100'] as int? ?? 10,
      minRedeemPoints: json['minimum_redeem_points'] as int? ?? 100,
      maxRedeemPercentage:
          (json['max_redeem_percentage'] as num?)?.toDouble() ?? 20.0,
    );
  }

  static const LoyaltySettingsModel defaults = LoyaltySettingsModel(
    isEnabled: true,
    earnEnabled: true,
    redeemEnabled: true,
    earnPer100: 10,
    minRedeemPoints: 100,
    maxRedeemPercentage: 20.0,
  );
}
