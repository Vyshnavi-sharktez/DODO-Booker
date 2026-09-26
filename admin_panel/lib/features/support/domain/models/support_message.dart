import 'package:intl/intl.dart';

class SupportMessage {
  final String id;
  final String conversationId;
  final String senderType;
  final String senderId;
  final String message;
  final bool isReadByAdmin;
  final bool isReadByCustomer;
  final DateTime createdAt;
  final String? attachmentUrl;
  final String? attachmentType;
  final String? contextType;
  final String? contextId;

  const SupportMessage({
    required this.id,
    required this.conversationId,
    required this.senderType,
    required this.senderId,
    required this.message,
    required this.isReadByAdmin,
    required this.isReadByCustomer,
    required this.createdAt,
    this.attachmentUrl,
    this.attachmentType,
    this.contextType,
    this.contextId,
  });

  factory SupportMessage.fromMap(Map<String, dynamic> m) {
    return SupportMessage(
      id: m['id'] as String,
      conversationId: m['conversation_id'] as String,
      senderType: m['sender_type'] as String,
      senderId: m['sender_id'] as String,
      message: m['message'] as String,
      isReadByAdmin: m['is_read_by_admin'] as bool? ?? false,
      isReadByCustomer: m['is_read_by_customer'] as bool? ?? false,
      createdAt: DateTime.parse(m['created_at'] as String),
      attachmentUrl: m['attachment_url'] as String?,
      attachmentType: m['attachment_type'] as String?,
      contextType: m['context_type'] as String?,
      contextId: m['context_id'] as String?,
    );
  }

  bool get isFromAdmin => senderType == 'admin';
  bool get hasAttachment =>
      attachmentUrl != null && attachmentUrl!.isNotEmpty;
  bool get hasContext => contextType != null && contextId != null;
  bool get isImageAttachment =>
      attachmentType != null && attachmentType!.startsWith('image/');

  static final _timeFmt = DateFormat('d MMM, h:mm a');
  String get formattedTime => _timeFmt.format(createdAt.toLocal());
}
