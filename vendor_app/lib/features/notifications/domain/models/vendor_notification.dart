enum NotificationType { booking, payment, system, promotion, reminder }

class VendorNotification {
  const VendorNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.type,
    this.isRead = false,
    this.bookingId,
    this.createdAt,
  });

  final String id;
  final String title;
  final String message;
  final NotificationType type;
  final bool isRead;
  final String? bookingId;
  final DateTime? createdAt;

  factory VendorNotification.fromMap(Map<String, dynamic> map) {
    return VendorNotification(
      id: map['id'] as String,
      title: map['title'] as String? ?? '',
      message: map['message'] as String? ?? '',
      type: NotificationType.values.firstWhere(
        (t) => t.name == (map['notification_type'] as String? ?? 'system'),
        orElse: () => NotificationType.system,
      ),
      isRead: map['is_read'] as bool? ?? false,
      bookingId: map['booking_id'] as String?,
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
      type: type,
      isRead: isRead ?? this.isRead,
      bookingId: bookingId,
      createdAt: createdAt,
    );
  }
}
