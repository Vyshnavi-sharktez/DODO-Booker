import 'package:supabase_flutter/supabase_flutter.dart';

class ServiceShowcaseRepository {
  final SupabaseClient _supabase;
  const ServiceShowcaseRepository(this._supabase);

  /// Currently showcased images for [nodeId], ordered by sort_order.
  /// Each row includes the joined booking_images (image_url, image_type).
  Future<List<Map<String, dynamic>>> fetchShowcasedImages(
      String nodeId) async {
    final data = await _supabase
        .from('service_showcase_images')
        .select(
            'booking_image_id, sort_order, booking_images(image_url, image_type)')
        .eq('catalog_node_id', nodeId)
        .order('sort_order');
    return List<Map<String, dynamic>>.from(data as List);
  }

  /// All before/after booking_images uploaded for bookings containing [nodeId].
  /// Used by the admin picker to show selectable images.
  Future<List<Map<String, dynamic>>> fetchAvailableImages(
      String nodeId) async {
    final items = await _supabase
        .from('booking_items')
        .select('booking_id')
        .eq('service_id', nodeId);

    final bookingIds =
        (items as List).map((e) => e['booking_id'] as String).toList();
    if (bookingIds.isEmpty) return [];

    final data = await _supabase
        .from('booking_images')
        .select('id, image_url, image_type, created_at')
        .inFilter('booking_id', bookingIds)
        .inFilter('image_type', ['before', 'after'])
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(data as List);
  }

  /// Inserts [bookingImageIds] into the showcase for [nodeId].
  /// Skips IDs that are already showcased. Sort order follows existing count.
  Future<void> addToShowcase(
      String nodeId, List<String> bookingImageIds) async {
    final existing = await _supabase
        .from('service_showcase_images')
        .select('booking_image_id, sort_order')
        .eq('catalog_node_id', nodeId)
        .order('sort_order', ascending: false);

    final existingIds = (existing as List)
        .map((e) => e['booking_image_id'] as String)
        .toSet();

    int nextOrder = existing.isEmpty
        ? 0
        : ((existing.first['sort_order'] as int) + 1);

    final newRows = <Map<String, dynamic>>[];
    for (final id in bookingImageIds) {
      if (!existingIds.contains(id)) {
        newRows.add({
          'catalog_node_id': nodeId,
          'booking_image_id': id,
          'sort_order': nextOrder++,
        });
      }
    }
    if (newRows.isEmpty) return;
    await _supabase.from('service_showcase_images').insert(newRows);
  }

  /// Removes [bookingImageId] from the showcase without touching booking_images.
  Future<void> removeFromShowcase(
      String nodeId, String bookingImageId) async {
    await _supabase
        .from('service_showcase_images')
        .delete()
        .eq('catalog_node_id', nodeId)
        .eq('booking_image_id', bookingImageId);
  }
}
