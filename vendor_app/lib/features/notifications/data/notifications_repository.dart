import '../../../shared/repositories/base_repository.dart';
import '../domain/models/vendor_notification.dart';

class NotificationsRepository extends BaseRepository {
  const NotificationsRepository(super.supabase);

  Future<List<VendorNotification>> fetchNotifications(
    String vendorId,
  ) async =>
      throw UnimplementedError();

  Future<void> markAsRead(String notificationId) async {}

  Future<void> markAllAsRead(String vendorId) async {}

  Future<void> deleteNotification(String notificationId) async {}
}
