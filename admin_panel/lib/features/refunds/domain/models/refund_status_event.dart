class RefundStatusEvent {
  final String id;
  final String refundRequestId;
  final String? fromStatus;
  final String toStatus;
  final String? changedBy;
  final String changedByType;
  final String? notes;
  final Map<String, dynamic> metadata;
  final DateTime createdAt;

  const RefundStatusEvent({
    required this.id,
    required this.refundRequestId,
    this.fromStatus,
    required this.toStatus,
    this.changedBy,
    required this.changedByType,
    this.notes,
    required this.metadata,
    required this.createdAt,
  });

  factory RefundStatusEvent.fromMap(Map<String, dynamic> m) =>
      RefundStatusEvent(
        id: m['id'] as String,
        refundRequestId: m['refund_request_id'] as String,
        fromStatus: m['from_status'] as String?,
        toStatus: m['to_status'] as String,
        changedBy: m['changed_by'] as String?,
        changedByType: m['changed_by_type'] as String? ?? 'admin',
        notes: m['notes'] as String?,
        metadata: (m['metadata'] as Map<String, dynamic>?) ?? {},
        createdAt: DateTime.parse(m['created_at'] as String),
      );
}
