import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'bookings_service.dart';
import '../../../models/my_booking_model.dart';

final bookingsServiceProvider = Provider<BookingsService>(
  (ref) => BookingsService(),
);

final myBookingsProvider = FutureProvider<List<MyBookingModel>>(
  (ref) => ref.read(bookingsServiceProvider).fetchMyBookings(),
);

final bookingByIdProvider =
    FutureProvider.family<MyBookingModel?, String>(
  (ref, id) => ref.read(bookingsServiceProvider).fetchBookingById(id),
);

final bookingImagesProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, bookingId) async {
  final rows = await Supabase.instance.client
      .from('booking_images')
      .select('image_type, image_url, created_at')
      .eq('booking_id', bookingId)
      .order('created_at');
  return List<Map<String, dynamic>>.from(rows as List);
});
