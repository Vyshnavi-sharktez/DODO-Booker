class RefundMessageModel {
  final String id;
  final String refundRequestId;
  final String senderType; // 'customer' | 'admin'
  final String? senderId;
  final String message;
  final String? attachmentUrl;        // legacy single-attachment column
  final List<String> attachmentUrls;  // multi-image (new)
  final bool isInternal;
  final DateTime createdAt;

  const RefundMessageModel({
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

  // All storage paths: merges legacy single-URL with the new array.
  List<String> get allAttachmentPaths {
    final merged = [...attachmentUrls];
    if (attachmentUrl != null &&
        attachmentUrl!.isNotEmpty &&
        !merged.contains(attachmentUrl)) {
      merged.insert(0, attachmentUrl!);
    }
    return merged;
  }

  factory RefundMessageModel.fromMap(Map<String, dynamic> map) {
    final rawUrls = map['attachment_urls'];
    final List<String> urls = rawUrls is List
        ? rawUrls.map((e) => e.toString()).toList()
        : <String>[];

    return RefundMessageModel(
      id: map['id'] as String,
      refundRequestId: map['refund_request_id'] as String,
      senderType: map['sender_type'] as String? ?? 'admin',
      senderId: map['sender_id'] as String?,
      message: map['message'] as String? ?? '',
      attachmentUrl: map['attachment_url'] as String?,
      attachmentUrls: urls,
      isInternal: map['is_internal'] as bool? ?? false,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
