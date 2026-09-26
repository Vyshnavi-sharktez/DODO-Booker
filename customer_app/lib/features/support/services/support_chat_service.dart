import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/models/support_conversation.dart';
import '../domain/models/support_message.dart';

String _newUuid() {
  final rng = math.Random.secure();
  final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
      '${hex.substring(20, 32)}';
}

class SupportChatService {
  static const _phoneKey = 'dodo_auth_phone';
  static const _bucket = 'support-chat-attachments';
  static const _maxBytes = 5 * 1024 * 1024;

  final _client = Supabase.instance.client;

  Future<String> _getCustomerId() async {
    final phone =
        (await SharedPreferences.getInstance()).getString(_phoneKey);
    if (phone == null) throw Exception('Not authenticated');
    final row = await _client
        .from('customers')
        .select('id')
        .eq('phone', phone)
        .single();
    return row['id'] as String;
  }

  Future<SupportConversation> getOrCreateConversation() async {
    final customerId = await _getCustomerId();
    final result = await _client.rpc(
      'support_get_or_create_conversation',
      params: {'p_customer_id': customerId},
    );
    debugPrint('[Support] getOrCreateConversation result=$result');
    return SupportConversation.fromMap(result as Map<String, dynamic>);
  }

  Future<List<SupportMessage>> getMessages(String conversationId) async {
    final customerId = await _getCustomerId();
    final result = await _client.rpc(
      'support_get_conversation_messages',
      params: {
        'p_customer_id': customerId,
        'p_conversation_id': conversationId,
      },
    );
    final rows = result as List;
    debugPrint('[Support] getMessages count=${rows.length}');
    return rows
        .map((m) => SupportMessage.fromMap(m as Map<String, dynamic>))
        .toList();
  }

  Future<String> sendMessage(
    String conversationId,
    String message, {
    String? messageId,
    String? attachmentUrl,
    String? attachmentType,
    String? contextType,
    String? contextId,
  }) async {
    final customerId = await _getCustomerId();
    final id = messageId ?? _newUuid();
    final result = await _client.rpc(
      'support_send_customer_message',
      params: {
        'p_customer_id': customerId,
        'p_conversation_id': conversationId,
        'p_message': message,
        'p_message_id': id,
        if (attachmentUrl != null) 'p_attachment_url': attachmentUrl,
        if (attachmentType != null) 'p_attachment_type': attachmentType,
        if (contextType != null) 'p_context_type': contextType,
        if (contextId != null) 'p_context_id': contextId,
      },
    );
    return result as String? ?? id;
  }

  Future<String> uploadAttachment({
    required String conversationId,
    required Uint8List bytes,
    required String filename,
    required String mimeType,
  }) async {
    if (bytes.length > _maxBytes) {
      final mb = (bytes.length / (1024 * 1024)).toStringAsFixed(1);
      throw Exception('File is ${mb}MB — maximum 5 MB allowed.');
    }
    final customerId = await _getCustomerId();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final safe = filename.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final path =
        'conversations/$conversationId/customer_$customerId/${ts}_$safe';
    await _client.storage.from(_bucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: mimeType, upsert: false),
        );
    return path;
  }

  Future<String?> getSignedAttachmentUrl(String storagePath) async {
    try {
      return await _client.storage
          .from(_bucket)
          .createSignedUrl(storagePath, 3600);
    } catch (e) {
      debugPrint('[Support] getSignedAttachmentUrl failed: $e');
      return null;
    }
  }

  Future<void> closeConversation() async {
    final customerId = await _getCustomerId();
    await _client.rpc(
      'support_customer_close_conversation',
      params: {'p_customer_id': customerId},
    );
  }

  Future<void> markRead(String conversationId) async {
    try {
      final customerId = await _getCustomerId();
      await _client.rpc(
        'support_mark_messages_read_by_customer',
        params: {
          'p_customer_id': customerId,
          'p_conversation_id': conversationId,
        },
      );
    } catch (e) {
      debugPrint('[Support] markRead error (non-fatal): $e');
    }
  }
}
