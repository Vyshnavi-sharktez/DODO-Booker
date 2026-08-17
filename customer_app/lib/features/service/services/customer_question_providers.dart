import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/customer_question_model.dart';
import 'customer_question_service.dart';

final customerQuestionServiceProvider = Provider<CustomerQuestionService>(
  (_) => CustomerQuestionService(),
);

final answeredCustomerQuestionsProvider =
    FutureProvider.family<List<CustomerQuestionModel>, String>(
  (ref, serviceId) => ref
      .read(customerQuestionServiceProvider)
      .fetchAnsweredForService(serviceId),
);
