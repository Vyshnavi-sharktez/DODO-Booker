import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/models/app_notification.dart';

class NotificationsRepository {
  final SupabaseClient _supabase;

  const NotificationsRepository(this._supabase);

  Future<List<AppNotification>> fetchNotifications() async {
    final data = await _supabase
        .from('notifications')
        .select()
        .order('created_at', ascending: false);
    return (data as List<dynamic>)
        .map((r) => AppNotification.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<AppNotification> createNotification({
    required String userType,
    required String userId,
    required String title,
    required String message,
    required String notificationType,
    String? entityType,
    String? entityId,
  }) async {
    final data = await _supabase
        .from('notifications')
        .insert({
          'user_type': userType,
          'user_id': userId,
          'title': title,
          'message': message,
          'notification_type': notificationType,
          'is_read': false,
          'entity_type': ?entityType,
          'entity_id': ?entityId,
        })
        .select()
        .single();
    return AppNotification.fromMap(data);
  }

  Future<void> updateReadStatus(String id, {required bool isRead}) async {
    await _supabase
        .from('notifications')
        .update({'is_read': isRead})
        .eq('id', id);
  }

  Future<void> bulkMarkAsRead(List<String> ids) async {
    if (ids.isEmpty) return;
    await _supabase
        .from('notifications')
        .update({'is_read': true})
        .inFilter('id', ids);
  }

  Future<void> deleteNotification(String id) async {
    await _supabase.from('notifications').delete().eq('id', id);
  }

  Future<void> bulkDelete(List<String> ids) async {
    if (ids.isEmpty) return;
    await _supabase
        .from('notifications')
        .delete()
        .inFilter('id', ids);
  }
}
