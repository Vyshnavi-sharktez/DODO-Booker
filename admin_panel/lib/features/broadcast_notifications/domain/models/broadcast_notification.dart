class BroadcastNotification {
  final String id;
  final String title;
  final String message;
  final String notificationType; // offer | new_service | announcement | custom
  final String audience; // customers | vendors | both
  final String? imageUrl;
  final String? deepLink;
  final String targetingType; // all | city | booked_service | booked_category
  final String? targetingValue;
  final String? targetingLabel;
  final String status; // draft | scheduled | sending | sent | failed
  final DateTime? scheduledAt;
  final DateTime? sentAt;
  final int recipientCount;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const BroadcastNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.notificationType,
    required this.audience,
    this.imageUrl,
    this.deepLink,
    required this.targetingType,
    this.targetingValue,
    this.targetingLabel,
    required this.status,
    this.scheduledAt,
    this.sentAt,
    required this.recipientCount,
    this.createdAt,
    this.updatedAt,
  });

  factory BroadcastNotification.fromMap(Map<String, dynamic> map) {
    return BroadcastNotification(
      id: map['id'] as String,
      title: map['title'] as String? ?? '',
      message: map['message'] as String? ?? '',
      notificationType: map['notification_type'] as String? ?? 'announcement',
      audience: map['audience'] as String? ?? 'customers',
      imageUrl: map['image_url'] as String?,
      deepLink: map['deep_link'] as String?,
      targetingType: map['targeting_type'] as String? ?? 'all',
      targetingValue: map['targeting_value'] as String?,
      targetingLabel: map['targeting_label'] as String?,
      status: map['status'] as String? ?? 'draft',
      scheduledAt: map['scheduled_at'] != null
          ? DateTime.tryParse(map['scheduled_at'] as String)
          : null,
      sentAt: map['sent_at'] != null
          ? DateTime.tryParse(map['sent_at'] as String)
          : null,
      recipientCount: (map['recipient_count'] as int?) ?? 0,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String)
          : null,
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'] as String)
          : null,
    );
  }

  BroadcastNotification copyWith({
    String? title,
    String? message,
    String? notificationType,
    String? audience,
    String? imageUrl,
    String? deepLink,
    String? targetingType,
    String? targetingValue,
    String? targetingLabel,
    String? status,
    DateTime? scheduledAt,
    DateTime? sentAt,
    int? recipientCount,
  }) {
    return BroadcastNotification(
      id: id,
      title: title ?? this.title,
      message: message ?? this.message,
      notificationType: notificationType ?? this.notificationType,
      audience: audience ?? this.audience,
      imageUrl: imageUrl ?? this.imageUrl,
      deepLink: deepLink ?? this.deepLink,
      targetingType: targetingType ?? this.targetingType,
      targetingValue: targetingValue ?? this.targetingValue,
      targetingLabel: targetingLabel ?? this.targetingLabel,
      status: status ?? this.status,
      scheduledAt: scheduledAt ?? this.scheduledAt,
      sentAt: sentAt ?? this.sentAt,
      recipientCount: recipientCount ?? this.recipientCount,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
