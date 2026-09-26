import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'support_chat_service.dart';
import '../domain/models/support_conversation.dart';
import '../domain/models/support_message.dart';

final supportChatServiceProvider = Provider<SupportChatService>(
  (ref) => SupportChatService(),
);

// Single conversation per customer — invalidated by realtime sync on support_reply
// notification so the screen detects new admin messages.
final supportConversationProvider =
    FutureProvider<SupportConversation>((ref) async {
  return ref.read(supportChatServiceProvider).getOrCreateConversation();
});

final supportMessagesProvider =
    FutureProvider.autoDispose.family<List<SupportMessage>, String>(
  (ref, conversationId) async {
    return ref.read(supportChatServiceProvider).getMessages(conversationId);
  },
);
