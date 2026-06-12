class ReviewModel {
  final String id;
  final String bookingId;
  final String customerId;
  final String? vendorId;
  final int rating;
  final String reviewText;
  final DateTime createdAt;

  const ReviewModel({
    required this.id,
    required this.bookingId,
    required this.customerId,
    this.vendorId,
    required this.rating,
    required this.reviewText,
    required this.createdAt,
  });

  factory ReviewModel.fromJson(Map<String, dynamic> json) {
    return ReviewModel(
      id: json['id'] as String,
      bookingId: json['booking_id'] as String,
      customerId: json['customer_id'] as String,
      vendorId: json['vendor_id'] as String?,
      rating: (json['rating'] as num).toInt(),
      reviewText: json['review_text'] as String? ?? '',
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
