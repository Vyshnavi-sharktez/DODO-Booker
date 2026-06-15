class VendorNotification {
  const VendorNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.notificationType,
    this.isRead = false,
    this.bookingId,
    this.entityType,
    this.entityId,
    this.createdAt,
  });

  final String id;
  final String title;
  final String message;
  final String notificationType;
  final bool isRead;
  final String? bookingId;
  final String? entityType;
  final String? entityId;
  final DateTime? createdAt;

  factory VendorNotification.fromMap(Map<String, dynamic> map) {
    return VendorNotification(
      id: map['id'] as String,
      title: map['title'] as String? ?? '',
      message: map['message'] as String? ?? '',
      notificationType: map['notification_type'] as String? ?? 'system',
      isRead: map['is_read'] as bool? ?? false,
      bookingId: map['booking_id'] as String?,
      entityType: map['entity_type'] as String?,
      entityId: map['entity_id'] as String?,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String)
          : null,
    );
  }

  VendorNotification copyWith({bool? isRead}) {
    return VendorNotification(
      id: id,
      title: title,
      message: message,
      notificationType: notificationType,
      isRead: isRead ?? this.isRead,
      bookingId: bookingId,
      entityType: entityType,
      entityId: entityId,
      createdAt: createdAt,
    );
  }
}
