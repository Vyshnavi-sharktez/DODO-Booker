class RefundTransactionModel {
  final String id;
  final String refundRequestId;
  final double amount;
  final String gateway;
  final String? gatewayRefundId;
  final String status; // pending | processing | completed | failed
  final String? failureReason;
  final String refundMethod;
  final DateTime createdAt;
  final DateTime? completedAt;

  const RefundTransactionModel({
    required this.id,
    required this.refundRequestId,
    required this.amount,
    required this.gateway,
    this.gatewayRefundId,
    required this.status,
    this.failureReason,
    required this.refundMethod,
    required this.createdAt,
    this.completedAt,
  });

  bool get isCompleted => status == 'completed';
  bool get isFailed => status == 'failed';
  bool get isPending => status == 'pending';
  bool get isProcessing => status == 'processing';

  factory RefundTransactionModel.fromMap(Map<String, dynamic> map) {
    return RefundTransactionModel(
      id: map['id'] as String,
      refundRequestId: map['refund_request_id'] as String,
      amount: (map['amount'] as num).toDouble(),
      gateway: map['gateway'] as String? ?? 'manual',
      gatewayRefundId: map['gateway_refund_id'] as String?,
      status: map['status'] as String? ?? 'pending',
      failureReason: map['failure_reason'] as String?,
      refundMethod: map['refund_method'] as String? ?? 'manual',
      createdAt: DateTime.parse(map['created_at'] as String),
      completedAt: map['completed_at'] != null
          ? DateTime.parse(map['completed_at'] as String)
          : null,
    );
  }
}
