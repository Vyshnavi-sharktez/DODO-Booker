class LoyaltyTransactionModel {
  final String id;
  final String? bookingId;
  final String type; // 'earn' | 'redeem'
  final int points;
  final String? description;
  final DateTime createdAt;

  const LoyaltyTransactionModel({
    required this.id,
    this.bookingId,
    required this.type,
    required this.points,
    this.description,
    required this.createdAt,
  });

  bool get isEarn => type == 'earn';

  factory LoyaltyTransactionModel.fromJson(Map<String, dynamic> json) {
    return LoyaltyTransactionModel(
      id: json['id'] as String,
      bookingId: json['booking_id'] as String?,
      type: json['type'] as String,
      points: json['points'] as int,
      description: json['description'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
