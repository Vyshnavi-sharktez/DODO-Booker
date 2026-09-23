import 'package:intl/intl.dart';

class RefundMessage {
  final String id;
  final String refundRequestId;
  final String senderType; // 'customer' | 'admin'
  final String? senderId;
  final String message;
  final String? attachmentUrl;        // legacy single-attachment column
  final List<String> attachmentUrls;  // multi-image (new)
  final bool isInternal;
  final DateTime createdAt;

  const RefundMessage({
    required this.id,
    required this.refundRequestId,
    required this.senderType,
    this.senderId,
    required this.message,
    this.attachmentUrl,
    required this.attachmentUrls,
    required this.isInternal,
    required this.createdAt,
  });

  bool get isFromCustomer => senderType == 'customer';
  bool get isFromAdmin => senderType == 'admin';

  // All image paths: merges legacy single-URL with the new array.
  List<String> get allAttachmentPaths {
    final merged = [...attachmentUrls];
    if (attachmentUrl != null &&
        attachmentUrl!.isNotEmpty &&
        !merged.contains(attachmentUrl)) {
      merged.insert(0, attachmentUrl!);
    }
    return merged;
  }

  String get formattedTime =>
      DateFormat('d MMM, h:mm a').format(createdAt.toLocal());

  factory RefundMessage.fromMap(Map<String, dynamic> m) {
    final rawUrls = m['attachment_urls'];
    final List<String> urls = rawUrls is List
        ? rawUrls.map((e) => e.toString()).toList()
        : <String>[];

    return RefundMessage(
      id: m['id'] as String,
      refundRequestId: m['refund_request_id'] as String,
      senderType: m['sender_type'] as String? ?? 'admin',
      senderId: m['sender_id'] as String?,
      message: m['message'] as String? ?? '',
      attachmentUrl: m['attachment_url'] as String?,
      attachmentUrls: urls,
      isInternal: m['is_internal'] as bool? ?? false,
      createdAt: DateTime.parse(m['created_at'] as String),
    );
  }
}
