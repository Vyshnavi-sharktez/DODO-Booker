import 'package:flutter/material.dart';

class SupportConversation {
  final String id;
  final String customerId;
  final String status;
  final DateTime? lastMessageAt;
  final String? lastMessagePreview;
  final int unreadCustomerCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  const SupportConversation({
    required this.id,
    required this.customerId,
    required this.status,
    this.lastMessageAt,
    this.lastMessagePreview,
    required this.unreadCustomerCount,
    required this.createdAt,
    required this.updatedAt,
  });

  factory SupportConversation.fromMap(Map<String, dynamic> m) {
    return SupportConversation(
      id: m['id'] as String,
      customerId: m['customer_id'] as String,
      status: m['status'] as String? ?? 'open',
      lastMessageAt: m['last_message_at'] != null
          ? DateTime.parse(m['last_message_at'] as String)
          : null,
      lastMessagePreview: m['last_message_preview'] as String?,
      unreadCustomerCount: (m['unread_customer_count'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.parse(m['created_at'] as String),
      updatedAt: DateTime.parse(m['updated_at'] as String),
    );
  }

  SupportConversation copyWith({String? status}) => SupportConversation(
        id: id,
        customerId: customerId,
        status: status ?? this.status,
        lastMessageAt: lastMessageAt,
        lastMessagePreview: lastMessagePreview,
        unreadCustomerCount: unreadCustomerCount,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

  bool get isClosed => status == 'closed';

  String get statusLabel {
    switch (status) {
      case 'pending_admin':
        return 'Awaiting Response';
      case 'pending_customer':
        return 'Reply Received';
      case 'closed':
        return 'Closed';
      default:
        return 'Open';
    }
  }

  Color get statusColor {
    switch (status) {
      case 'pending_admin':
        return const Color(0xFFE67E22);
      case 'pending_customer':
        return const Color(0xFF38A169);
      case 'closed':
        return const Color(0xFF9E9E9E);
      default:
        return const Color(0xFF3B82F6);
    }
  }
}
