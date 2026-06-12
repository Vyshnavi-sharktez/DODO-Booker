import 'package:flutter_riverpod/flutter_riverpod.dart';
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
