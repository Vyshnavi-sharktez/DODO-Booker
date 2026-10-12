import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/models/broadcast_notification.dart';

class BroadcastNotificationsRepository {
  final SupabaseClient _supabase;

  const BroadcastNotificationsRepository(this._supabase);

  Future<List<BroadcastNotification>> fetchBroadcasts() async {
    final data = await _supabase
        .from('broadcast_notifications')
        .select()
        .order('created_at', ascending: false);
    return (data as List<dynamic>)
        .map((r) =>
            BroadcastNotification.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<BroadcastNotification> createBroadcast({
    required String title,
    required String message,
    required String notificationType,
    required String audience,
    String? imageUrl,
    String? deepLink,
    required String targetingType,
    String? targetingValue,
    String? targetingLabel,
    required String status, // 'draft' or 'scheduled'
    DateTime? scheduledAt,
    String? createdBy,
  }) async {
    final data = await _supabase
        .from('broadcast_notifications')
        .insert({
          'title': title,
          'message': message,
          'notification_type': notificationType,
          'audience': audience,
          if (imageUrl != null && imageUrl.isNotEmpty) 'image_url': imageUrl,
          if (deepLink != null && deepLink.isNotEmpty) 'deep_link': deepLink,
          'targeting_type': targetingType,
          if (targetingValue != null) 'targeting_value': targetingValue,
          if (targetingLabel != null) 'targeting_label': targetingLabel,
          'status': status,
          if (scheduledAt != null) 'scheduled_at': scheduledAt.toIso8601String(),
          if (createdBy != null) 'created_by': createdBy,
        })
        .select()
        .single();
    return BroadcastNotification.fromMap(data);
  }

  Future<void> deleteBroadcast(String id) async {
    await _supabase.from('broadcast_notifications').delete().eq('id', id);
  }

  /// Calls the send_broadcast_notification RPC which inserts notification rows
  /// (triggering push delivery) and marks the broadcast as sent.
  /// Returns the number of recipients notified.
  Future<int> sendBroadcast(String id) async {
    final result = await _supabase.rpc(
      'send_broadcast_notification',
      params: {'p_broadcast_id': id},
    );
    return (result as int?) ?? 0;
  }

  /// Returns available targeting values for the given type + audience.
  Future<List<({String value, String label})>> getTargetingOptions({
    required String targetingType,
    required String audience,
  }) async {
    final data = await _supabase.rpc(
      'get_broadcast_targeting_options',
      params: {
        'p_targeting_type': targetingType,
        'p_audience': audience,
      },
    );
    return (data as List<dynamic>).map((row) {
      final r = row as Map<String, dynamic>;
      return (
        value: r['value'] as String,
        label: r['label'] as String,
      );
    }).toList();
  }
}
