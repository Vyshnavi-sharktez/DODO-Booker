import 'package:flutter/material.dart';

class SupportConversation {
  final String id;
  final String customerId;
  final String status;
  final DateTime? lastMessageAt;
  final String? lastMessagePreview;
  final int unreadAdminCount;
  final int unreadCustomerCount;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? customerName;
  final String? customerPhone;
  final String? customerEmail;
  // Set when the customer started a new episode after a prior closed one.
  final DateTime? currentEpisodeStartedAt;
  // True for synthetic "Prior Episode" entries shown in the Closed tab.
  final bool viewAsHistory;

  const SupportConversation({
    required this.id,
    required this.customerId,
    required this.status,
    this.lastMessageAt,
    this.lastMessagePreview,
    required this.unreadAdminCount,
    required this.unreadCustomerCount,
    required this.createdAt,
    required this.updatedAt,
    this.customerName,
    this.customerPhone,
    this.customerEmail,
    this.currentEpisodeStartedAt,
    this.viewAsHistory = false,
  });

  factory SupportConversation.fromMap(
    Map<String, dynamic> m, {
    bool viewAsHistory = false,
  }) {
    final customer = m['customers'] as Map<String, dynamic>?;
    return SupportConversation(
      id: m['id'] as String,
      customerId: m['customer_id'] as String,
      status: m['status'] as String? ?? 'open',
      lastMessageAt: m['last_message_at'] != null
          ? DateTime.parse(m['last_message_at'] as String)
          : null,
      lastMessagePreview: m['last_message_preview'] as String?,
      unreadAdminCount: (m['unread_admin_count'] as num?)?.toInt() ?? 0,
      unreadCustomerCount: (m['unread_customer_count'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.parse(m['created_at'] as String),
      updatedAt: DateTime.parse(m['updated_at'] as String),
      customerName: customer?['full_name'] as String?,
      customerPhone: customer?['phone'] as String?,
      customerEmail: customer?['email'] as String?,
      currentEpisodeStartedAt: m['current_episode_started_at'] != null
          ? DateTime.parse(m['current_episode_started_at'] as String)
          : null,
      viewAsHistory: viewAsHistory,
    );
  }

  String get statusLabel {
    switch (status) {
      case 'pending_admin':
        return 'Needs Reply';
      case 'pending_customer':
        return 'Awaiting Customer';
      case 'closed':
        return 'Closed';
      default:
        return 'Open';
    }
  }

  Color get statusColor {
    switch (status) {
      case 'pending_admin':
        return const Color(0xFFE53E3E);
      case 'pending_customer':
        return const Color(0xFF38A169);
      case 'closed':
        return const Color(0xFF718096);
      default:
        return const Color(0xFF3182CE);
    }
  }

  bool get isClosed => status == 'closed';
}
