import '../../../shared/repositories/base_repository.dart';
import '../domain/models/vendor_notification.dart';

class NotificationsRepository extends BaseRepository {
  const NotificationsRepository(super.supabase);

  Future<List<VendorNotification>> fetchNotifications(String vendorId) async {
    final data = await supabase
        .from('notifications')
        .select()
        .eq('user_type', 'vendor')
        .eq('user_id', vendorId)
        .order('created_at', ascending: false);
    return (data as List)
        .map((r) => VendorNotification.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<void> markAsRead(String notificationId) async {
    await supabase
        .from('notifications')
        .update({'is_read': true}).eq('id', notificationId);
  }

  Future<void> markAllAsRead(String vendorId) async {
    await supabase
        .from('notifications')
        .update({'is_read': true})
        .eq('user_type', 'vendor')
        .eq('user_id', vendorId)
        .eq('is_read', false);
  }
}
