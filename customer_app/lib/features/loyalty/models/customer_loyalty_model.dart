class CustomerLoyaltyModel {
  final int availablePoints;
  final int lifetimeEarned;

  const CustomerLoyaltyModel({
    required this.availablePoints,
    required this.lifetimeEarned,
  });

  factory CustomerLoyaltyModel.fromJson(Map<String, dynamic> json) {
    return CustomerLoyaltyModel(
      availablePoints: json['available_points'] as int? ?? 0,
      lifetimeEarned: json['lifetime_earned'] as int? ?? 0,
    );
  }

  static const CustomerLoyaltyModel empty =
      CustomerLoyaltyModel(
        availablePoints: 0,
        lifetimeEarned: 0,
      );
}