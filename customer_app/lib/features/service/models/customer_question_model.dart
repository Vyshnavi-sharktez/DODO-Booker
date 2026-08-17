class CustomerQuestionModel {
  final String id;
  final String serviceId;
  final String customerId;
  final String? customerName;
  final String question;
  final String status;
  final String? answer;
  final DateTime? answeredAt;
  final DateTime createdAt;

  const CustomerQuestionModel({
    required this.id,
    required this.serviceId,
    required this.customerId,
    this.customerName,
    required this.question,
    required this.status,
    this.answer,
    this.answeredAt,
    required this.createdAt,
  });

  bool get isAnswered => status == 'answered';

  factory CustomerQuestionModel.fromJson(Map<String, dynamic> json) {
    return CustomerQuestionModel(
      id: json['id'] as String,
      serviceId: json['service_id'] as String,
      customerId: json['customer_id'] as String,
      customerName: json['customer_name'] as String?,
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
