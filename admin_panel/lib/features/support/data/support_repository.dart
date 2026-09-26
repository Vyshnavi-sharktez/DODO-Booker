import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/models/support_conversation.dart';
import '../domain/models/support_message.dart';

class SupportRepository {
  final SupabaseClient _supabase;

  const SupportRepository(this._supabase);

  // ── Conversations list ────────────────────────────────────────────────────

  static const _kConvSelect =
      'id, customer_id, status, last_message_at, last_message_preview, '
      'unread_admin_count, unread_customer_count, created_at, updated_at, '
      'current_episode_started_at, customers(full_name, phone, email)';

  Future<List<SupportConversation>> fetchConversations({
    String? statusFilter,
    String? search,
  }) async {
    List<SupportConversation> results;

    if (statusFilter == 'closed') {
      // 1. Conversations currently closed (show their current — and only — episode).
      final closedData = await _supabase
          .from('support_conversations')
          .select(_kConvSelect)
          .eq('status', 'closed')
          .order('updated_at', ascending: false);

      // 2. Active conversations that have a prior closed episode to browse.
      final historyData = await _supabase
          .from('support_conversations')
          .select(_kConvSelect)
          .neq('status', 'closed')
          .not('current_episode_started_at', 'is', null)
          .order('updated_at', ascending: false);

      results = [
        ...(closedData as List<dynamic>).map(
            (r) => SupportConversation.fromMap(r as Map<String, dynamic>)),
        ...(historyData as List<dynamic>).map((r) => SupportConversation.fromMap(
            r as Map<String, dynamic>,
            viewAsHistory: true)),
      ];
      results.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    } else {
      var query =
          _supabase.from('support_conversations').select(_kConvSelect);

      if (statusFilter == 'all') {
        // no filter
      } else if (statusFilter == 'active') {
        query = query.neq('status', 'closed');
      } else if (statusFilter != null) {
        query = query.eq('status', statusFilter);
      }

      final data = await query.order('updated_at', ascending: false);
      results = (data as List<dynamic>)
          .map((r) => SupportConversation.fromMap(r as Map<String, dynamic>))
          .toList();
    }

    if (search != null && search.isNotEmpty) {
      final q = search.toLowerCase();
      results = results.where((c) {
        return (c.customerName?.toLowerCase().contains(q) ?? false) ||
            (c.customerPhone?.contains(q) ?? false);
      }).toList();
    }

    return results;
  }

  // ── Single conversation ───────────────────────────────────────────────────

  Future<SupportConversation?> fetchConversationById(String id) async {
    final data = await _supabase
        .from('support_conversations')
        .select(_kConvSelect)
        .eq('id', id)
        .maybeSingle();

    if (data == null) return null;
    return SupportConversation.fromMap(data);
  }

  // ── Messages ──────────────────────────────────────────────────────────────

  Future<List<SupportMessage>> fetchMessages(
    String conversationId, {
    bool viewHistory = false,
  }) async {
    final convRow = await _supabase
        .from('support_conversations')
        .select('current_episode_started_at')
        .eq('id', conversationId)
        .single();
    final episodeStart = convRow['current_episode_started_at'] as String?;

    var query = _supabase
        .from('support_messages')
        .select(
          'id, conversation_id, sender_type, sender_id, message, '
          'is_read_by_admin, is_read_by_customer, created_at, '
          'attachment_url, attachment_type, context_type, context_id',
        )
        .eq('conversation_id', conversationId);

    if (episodeStart != null) {
      // viewHistory: show messages before the current episode (prior closed msgs)
      // normal: show messages in the current episode only
      query = viewHistory
          ? query.lt('created_at', episodeStart)
          : query.gte('created_at', episodeStart);
    }

    final data = await query.order('created_at', ascending: true);
    return (data as List<dynamic>)
        .map((r) => SupportMessage.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  // ── Admin send ────────────────────────────────────────────────────────────

  Future<void> sendAdminMessage(
    String conversationId,
    String message, {
    String? messageId,
    String? attachmentUrl,
    String? attachmentType,
    String? contextType,
    String? contextId,
  }) async {
    final adminUserId = _supabase.auth.currentUser?.id;
    final row = <String, dynamic>{
      'conversation_id': conversationId,
      'sender_type': 'admin',
      'sender_id': adminUserId,
      'message': message.trim(),
    };
    if (messageId != null) row['id'] = messageId;
    if (attachmentUrl != null) row['attachment_url'] = attachmentUrl;
    if (attachmentType != null) row['attachment_type'] = attachmentType;
    if (contextType != null) row['context_type'] = contextType;
    if (contextId != null) row['context_id'] = contextId;

    await _supabase.from('support_messages').insert(row);
  }

  // ── Mark read / close ─────────────────────────────────────────────────────

  Future<void> markConversationRead(String conversationId) async {
    await _supabase.rpc(
      'admin_mark_support_conversation_read',
      params: {'p_conversation_id': conversationId},
    );
  }

  Future<void> closeConversation(String conversationId) async {
    await _supabase.rpc(
      'admin_close_support_conversation',
      params: {'p_conversation_id': conversationId},
    );
  }

  // ── Attachments ───────────────────────────────────────────────────────────

  static const _bucket = 'support-chat-attachments';
  static const _maxBytes = 5 * 1024 * 1024; // 5 MB

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
    final adminId = _supabase.auth.currentUser?.id ?? 'unknown';
    final ts = DateTime.now().millisecondsSinceEpoch;
    final safe = filename.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final path = 'conversations/$conversationId/admin_$adminId/${ts}_$safe';
    await _supabase.storage.from(_bucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: mimeType, upsert: false),
        );
    return path;
  }

  Future<String?> getSignedAttachmentUrl(String storagePath) async {
    try {
      return await _supabase.storage
          .from(_bucket)
          .createSignedUrl(storagePath, 3600);
    } catch (e) {
      debugPrint('[Support] getSignedAttachmentUrl failed: $e');
      return null;
    }
  }

  // ── Context link helpers ──────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchCustomerBookings(
      String customerId) async {
    final data = await _supabase
        .from('bookings')
        .select('id, booking_number, status, service_date, total_amount')
        .eq('customer_id', customerId)
        .order('created_at', ascending: false)
        .limit(30);
    return (data as List).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> fetchCustomerRefunds(
      String customerId) async {
    final data = await _supabase
        .from('refund_requests')
        .select('id, ticket_number, status, created_at, requested_amount')
        .eq('customer_id', customerId)
        .order('created_at', ascending: false)
        .limit(20);
    return (data as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>?> fetchBookingById(String bookingId) async {
    final data = await _supabase
        .from('bookings')
        .select('id, booking_number, status, service_date, total_amount')
        .eq('id', bookingId)
        .maybeSingle();
    return data;
  }

  Future<Map<String, dynamic>?> fetchRefundById(String refundId) async {
    final data = await _supabase
        .from('refund_requests')
        .select('id, ticket_number, status, requested_amount')
        .eq('id', refundId)
        .maybeSingle();
    return data;
  }
}
