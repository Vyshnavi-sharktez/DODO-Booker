import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/notification_model.dart';

class NotificationService {
  static const _phoneKey = 'dodo_auth_phone';
  final _client = Supabase.instance.client;

  // Customer ID is stable per phone number. Cached after the first DB lookup
  // so that re-fetches (e.g., after markAsRead) skip the extra network roundtrip.
  // Keyed by phone so a different user logging in on the same device gets a
  // fresh lookup rather than the previous user's ID.
  String? _cachedPhone;
  String? _cachedCustomerId;

  Future<String> _getCustomerId() async {
    final phone = (await SharedPreferences.getInstance()).getString(_phoneKey);
    if (phone == null) throw Exception('Not authenticated');
    if (phone != _cachedPhone) {
      _cachedPhone = phone;
      _cachedCustomerId = null;
    }
    if (_cachedCustomerId != null) return _cachedCustomerId!;
    final row = await _client
        .from('customers')
        .select('id')
        .eq('phone', phone)
        .single();
    _cachedCustomerId = row['id'] as String;
    return _cachedCustomerId!;
  }

  /// Loads personal notifications (user_id = customerId) plus broadcast
  /// notifications (user_type = 'customer' AND user_id IS NULL).
  Future<List<NotificationModel>> fetchNotifications() async {
    final customerId = await _getCustomerId();
    debugPrint('[DODO][Notification] Loading for customer_id=$customerId');

    final data = await _client
        .from('notifications')
        .select('*')
        .or('user_id.eq.$customerId,and(user_type.eq.customer,user_id.is.null)')
        .order('created_at', ascending: false);

    final notifications = (data as List)
        .map((e) => NotificationModel.fromJson(e as Map<String, dynamic>))
        .toList();

    debugPrint('[DODO][Notification] Loaded: ${notifications.length} notifications');
    return notifications;
  }

  Future<void> markAsRead(String notificationId) async {
    debugPrint('[DODO][Notification] Marked Read: $notificationId');
    await _client
        .from('notifications')
        .update({'is_read': true})
        .eq('id', notificationId);
  }
}
