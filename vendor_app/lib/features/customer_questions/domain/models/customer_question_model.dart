class CustomerQuestionModel {
  const CustomerQuestionModel({
    required this.id,
    required this.customServiceId,
    required this.customerId,
    this.customerName,
    this.customerPhone,
    required this.question,
    required this.status,
    this.answer,
    this.answeredAt,
    required this.createdAt,
  });

  final String id;
  final String customServiceId;
  final String customerId;
  final String? customerName;
  final String? customerPhone;
  final String question;
  final String status;
  final String? answer;
  final DateTime? answeredAt;
  final DateTime createdAt;

  bool get isPending => status == 'pending';
  bool get isAnswered => status == 'answered';

  factory CustomerQuestionModel.fromJson(Map<String, dynamic> json) {
    return CustomerQuestionModel(
      id: json['id'] as String,
      customServiceId: json['custom_service_id'] as String,
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
