class NotificationModel {
  final String id;
  final String? userId;
  final String userType;
  final String title;
  final String message;
  final String? notificationType;
  final bool isRead;
  final DateTime createdAt;
  final String? entityType;
  final String? entityId;

  const NotificationModel({
    required this.id,
    this.userId,
    required this.userType,
    required this.title,
    required this.message,
    this.notificationType,
    required this.isRead,
    required this.createdAt,
    this.entityType,
    this.entityId,
  });

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    return NotificationModel(
      id: json['id'] as String,
      userId: json['user_id'] as String?,
      userType: json['user_type'] as String? ?? 'customer',
      title: json['title'] as String? ?? '',
      message: json['message'] as String? ?? '',
      notificationType: json['notification_type'] as String?,
      isRead: json['is_read'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
      entityType: json['entity_type'] as String?,
      entityId: json['entity_id'] as String?,
    );
  }
}
