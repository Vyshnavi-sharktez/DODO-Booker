class RefundStatusEventModel {
  final String id;
  final String refundRequestId;
  final String? fromStatus;
  final String? toStatus;
  final String changedByType; // 'admin' | 'customer' | 'system'
  final String? notes;
  final DateTime createdAt;

  const RefundStatusEventModel({
    required this.id,
    required this.refundRequestId,
    this.fromStatus,
    this.toStatus,
    required this.changedByType,
    this.notes,
    required this.createdAt,
  });

  factory RefundStatusEventModel.fromMap(Map<String, dynamic> map) {
    return RefundStatusEventModel(
      id: map['id'] as String,
      refundRequestId: map['refund_request_id'] as String,
      fromStatus: map['from_status'] as String?,
      toStatus: map['to_status'] as String?,
      changedByType: map['changed_by_type'] as String? ?? 'system',
      notes: map['notes'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
