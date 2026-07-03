class BookingImage {
  const BookingImage({
    required this.id,
    required this.bookingId,
    required this.imageType,
    required this.imageUrl,
    this.uploadedBy,
    this.createdAt,
  });

  final String id;
  final String bookingId;
  final String imageType; // 'before' | 'after'
  final String imageUrl;
  final String? uploadedBy;
  final DateTime? createdAt;

  factory BookingImage.fromMap(Map<String, dynamic> map) => BookingImage(
        id: map['id'] as String,
        bookingId: map['booking_id'] as String,
        imageType: map['image_type'] as String,
        imageUrl: map['image_url'] as String,
        uploadedBy: map['uploaded_by'] as String?,
        createdAt: map['created_at'] != null
            ? DateTime.parse(map['created_at'] as String)
            : null,
      );
}
