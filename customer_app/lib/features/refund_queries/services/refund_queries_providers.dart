import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'refund_queries_service.dart';
import '../models/customer_refund_model.dart';
import '../models/refund_issue_category_model.dart';
import '../models/booking_for_refund_model.dart';
import '../../auth/providers/auth_provider.dart';

final refundQueriesServiceProvider = Provider<RefundQueriesService>(
  (_) => RefundQueriesService(),
);

/// All refund requests for the signed-in customer.
/// Returns empty list when unauthenticated.
final myRefundQueriesProvider =
    FutureProvider<List<CustomerRefundModel>>((ref) async {
  final isAuth = ref.watch(isAuthenticatedProvider);
  if (!isAuth) return [];
  return ref.read(refundQueriesServiceProvider).fetchMyRefundRequests();
});

/// Single refund request with full detail (history, transactions, messages).
final refundQueryDetailProvider = FutureProvider.autoDispose
    .family<CustomerRefundModel?, String>((ref, id) {
  return ref.read(refundQueriesServiceProvider).fetchRefundRequestById(id);
});

/// Issue categories for the refund form.
final refundIssueCategoriesProvider =
    FutureProvider<List<RefundIssueCategoryModel>>((ref) {
  return ref.read(refundQueriesServiceProvider).fetchIssueCategories();
});

/// Bookings eligible for a new refund request.
final bookingsForRefundProvider =
    FutureProvider<List<BookingForRefundModel>>((ref) {
  final isAuth = ref.watch(isAuthenticatedProvider);
  if (!isAuth) return Future.value([]);
  return ref.read(refundQueriesServiceProvider).fetchBookingsForRefund();
});

/// Global refund policy description (optional — may be null).
final refundPolicyDescriptionProvider =
    FutureProvider<String?>((ref) {
  return ref
      .read(refundQueriesServiceProvider)
      .fetchRefundPolicyDescription();
});
