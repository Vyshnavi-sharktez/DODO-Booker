// Named AppNotification to avoid collision with Flutter's Notification class.
class AppNotification {
  final String id;
  final String userType;
  final String userId;
  final String title;
  final String message;
  final String notificationType;
  final bool isRead;
  final DateTime? createdAt;
  final String? entityType;
  final String? entityId;

  const AppNotification({
    required this.id,
    required this.userType,
    required this.userId,
    required this.title,
    required this.message,
    required this.notificationType,
    required this.isRead,
    this.createdAt,
    this.entityType,
    this.entityId,
  });

  factory AppNotification.fromMap(Map<String, dynamic> map) {
    return AppNotification(
      id: map['id'] as String,
      userType: map['user_type'] as String? ?? '',
      userId: map['user_id'] as String? ?? '',
      title: map['title'] as String? ?? '',
      message: map['message'] as String? ?? '',
      notificationType: map['notification_type'] as String? ?? '',
      isRead: map['is_read'] as bool? ?? false,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String)
          : null,
      entityType: map['entity_type'] as String?,
      entityId: map['entity_id'] as String?,
    );
  }

  AppNotification copyWith({bool? isRead}) {
    return AppNotification(
      id: id,
      userType: userType,
      userId: userId,
      title: title,
      message: message,
      notificationType: notificationType,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt,
      entityType: entityType,
      entityId: entityId,
    );
  }
}
