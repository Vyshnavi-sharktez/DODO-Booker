class ServiceFaq {
  final String id;
  final String serviceId;
  final String question;
  final String answer;
  final int sortOrder;

  const ServiceFaq({
    required this.id,
    required this.serviceId,
    required this.question,
    required this.answer,
    required this.sortOrder,
  });

  factory ServiceFaq.fromMap(Map<String, dynamic> map) {
    return ServiceFaq(
      id: map['id'] as String,
      serviceId: map['service_id'] as String,
      question: map['question'] as String? ?? '',
      answer: map['answer'] as String? ?? '',
      sortOrder: map['sort_order'] as int? ?? 0,
    );
  }
}
