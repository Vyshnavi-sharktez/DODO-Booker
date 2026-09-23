import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/refund_repository.dart';
import '../domain/models/refund_request.dart';
import '../domain/models/refund_issue_category.dart';
import '../domain/models/refund_message.dart';

final refundRepositoryProvider = Provider<RefundRepository>((ref) {
  return RefundRepository(Supabase.instance.client);
});

// ── Issue categories ──────────────────────────────────────────────────────────

final refundIssueCategoriesProvider =
    FutureProvider<List<RefundIssueCategory>>((ref) {
  return ref.read(refundRepositoryProvider).fetchIssueCategories();
});

// ── Refund request list ───────────────────────────────────────────────────────

final refundStatusFilterProvider = StateProvider<String>((ref) => 'all');
final refundSearchQueryProvider = StateProvider<String>((ref) => '');

final refundRequestsProvider =
    FutureProvider<List<RefundRequest>>((ref) async {
  final statusFilter = ref.watch(refundStatusFilterProvider);
  final search = ref.watch(refundSearchQueryProvider);
  return ref.read(refundRepositoryProvider).fetchRefundRequests(
        statusFilter: statusFilter,
        search: search.isEmpty ? null : search,
      );
});

// ── Single ticket detail ──────────────────────────────────────────────────────

final refundRequestDetailProvider =
    FutureProvider.autoDispose.family<RefundRequest?, String>((ref, id) {
  return ref.read(refundRepositoryProvider).fetchRefundRequestById(id);
});

// ── Messages for a single ticket (admin view, includes internal notes) ────────

final refundAdminMessagesProvider =
    FutureProvider.autoDispose.family<List<RefundMessage>, String>((ref, id) {
  return ref.read(refundRepositoryProvider).fetchMessages(id);
});
