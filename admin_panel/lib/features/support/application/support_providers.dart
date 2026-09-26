import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/support_repository.dart';
import '../domain/models/support_conversation.dart';
import '../domain/models/support_message.dart';

final supportRepositoryProvider = Provider<SupportRepository>((ref) {
  return SupportRepository(Supabase.instance.client);
});

// ── Filter / selection state ──────────────────────────────────────────────────

final supportStatusFilterProvider = StateProvider<String>((ref) => 'active');
final supportSearchQueryProvider = StateProvider<String>((ref) => '');
final selectedSupportConversationIdProvider =
    StateProvider<String?>((ref) => null);
// True when admin is viewing a prior closed episode (not the live conversation).
final selectedSupportHistoryModeProvider = StateProvider<bool>((ref) => false);

// Search query within the open chat pane (client-side filter).
final supportMessageSearchProvider = StateProvider<String>((ref) => '');

// ── Data providers ────────────────────────────────────────────────────────────

final supportConversationsProvider =
    FutureProvider<List<SupportConversation>>((ref) {
  final statusFilter = ref.watch(supportStatusFilterProvider);
  final search = ref.watch(supportSearchQueryProvider);
  return ref.read(supportRepositoryProvider).fetchConversations(
        statusFilter: statusFilter,
        search: search.isEmpty ? null : search,
      );
});

final supportConversationDetailProvider =
    FutureProvider.autoDispose.family<SupportConversation?, String>((ref, id) {
  return ref.read(supportRepositoryProvider).fetchConversationById(id);
});

final supportMessagesProvider =
    FutureProvider.autoDispose.family<List<SupportMessage>, String>((ref, id) {
  return ref.read(supportRepositoryProvider).fetchMessages(id);
});

final supportHistoricalMessagesProvider =
    FutureProvider.autoDispose.family<List<SupportMessage>, String>((ref, id) {
  return ref
      .read(supportRepositoryProvider)
      .fetchMessages(id, viewHistory: true);
});
