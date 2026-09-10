class CustomerQuestion {
  final String id;
  final String? serviceId;
  final String? customServiceId;
  final String? vendorId;
  final String? parentNodeId;
  final String customerId;
  final String? customerName;
  final String? customerPhone;
  final String question;
  final String status;
  final String? answer;
  final DateTime? answeredAt;
  final DateTime createdAt;

  const CustomerQuestion({
    required this.id,
    this.serviceId,
    this.customServiceId,
    this.vendorId,
    this.parentNodeId,
    required this.customerId,
    this.customerName,
    this.customerPhone,
    required this.question,
    required this.status,
    this.answer,
    this.answeredAt,
    required this.createdAt,
  });

  bool get isPending => status == 'pending';
  bool get isAnswered => status == 'answered';
  bool get isCustomServiceQuestion => customServiceId != null;

  factory CustomerQuestion.fromJson(Map<String, dynamic> json) {
    return CustomerQuestion(
      id: json['id'] as String,
      serviceId: json['service_id'] as String?,
      customServiceId: json['custom_service_id'] as String?,
      vendorId: json['vendor_id'] as String?,
      parentNodeId: json['parent_node_id'] as String?,
      customerId: json['customer_id'] as String,
      customerName: json['customer_name'] as String?,
      customerPhone: json['customer_phone'] as String?,
      question: json['question'] as String,
      status: (json['status'] as String?) ?? 'pending',
      answer: json['answer'] as String?,
      answeredAt: json['answered_at'] != null
          ? DateTime.parse(json['answered_at'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
