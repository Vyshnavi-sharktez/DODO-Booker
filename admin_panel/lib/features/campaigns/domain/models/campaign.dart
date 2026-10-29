class Campaign {
  final String id;
  final String name;
  final String channel; // 'sms' | 'whatsapp'
  final String message;
  final String templateId;
  final String templateLanguage;
  final String targetingType; // 'all' | 'city' | 'booked_service' | 'booked_category'
  final String? targetingValue;
  final String? targetingLabel;
  final bool isTestMode;
  final String status; // 'draft' | 'sending' | 'sent' | 'failed' | 'cancelled'
  final int? estimatedCount;
  final int recipientCount;
  final int sentCount;
  final int failedCount;
  final List<Map<String, dynamic>>? failureSummary;
  final String? createdBy;
  final DateTime? sentAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Campaign({
    required this.id,
    required this.name,
    required this.channel,
    required this.message,
    required this.templateId,
    required this.templateLanguage,
    required this.targetingType,
    this.targetingValue,
    this.targetingLabel,
    required this.isTestMode,
    required this.status,
    this.estimatedCount,
    required this.recipientCount,
    required this.sentCount,
    required this.failedCount,
    this.failureSummary,
    this.createdBy,
    this.sentAt,
    this.createdAt,
    this.updatedAt,
  });

  factory Campaign.fromMap(Map<String, dynamic> m) {
    List<Map<String, dynamic>>? summary;
    if (m['failure_summary'] != null) {
      final raw = m['failure_summary'] as List<dynamic>;
      summary = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return Campaign(
      id: m['id'] as String,
      name: m['name'] as String? ?? '',
      channel: m['channel'] as String? ?? 'sms',
      message: m['message'] as String? ?? '',
      templateId: m['template_id'] as String? ?? '',
      templateLanguage: m['template_language'] as String? ?? 'en',
      targetingType: m['targeting_type'] as String? ?? 'all',
      targetingValue: m['targeting_value'] as String?,
      targetingLabel: m['targeting_label'] as String?,
      isTestMode: m['is_test_mode'] as bool? ?? true,
      status: m['status'] as String? ?? 'draft',
      estimatedCount: m['estimated_count'] as int?,
      recipientCount: m['recipient_count'] as int? ?? 0,
      sentCount: m['sent_count'] as int? ?? 0,
      failedCount: m['failed_count'] as int? ?? 0,
      failureSummary: summary,
      createdBy: m['created_by'] as String?,
      sentAt: m['sent_at'] != null ? DateTime.tryParse(m['sent_at'] as String) : null,
      createdAt: m['created_at'] != null ? DateTime.tryParse(m['created_at'] as String) : null,
      updatedAt: m['updated_at'] != null ? DateTime.tryParse(m['updated_at'] as String) : null,
    );
  }

  bool get isDraft => status == 'draft';
  bool get isSending => status == 'sending';
  bool get isSent => status == 'sent';
  bool get isFailed => status == 'failed';
  bool get canSend => isDraft;
  bool get canReset => isFailed;
  bool get canDelete => isDraft || isFailed || status == 'cancelled';
}
