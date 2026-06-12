import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/supabase_client_provider.dart';
import '../../data/bookings_repository.dart';
import '../../domain/models/booking.dart';

final bookingsRepositoryProvider = Provider<BookingsRepository>(
  (ref) => BookingsRepository(ref.watch(supabaseClientProvider)),
);

class BookingsNotifier extends StateNotifier<AsyncValue<List<Booking>>> {
  BookingsNotifier(this._repo) : super(const AsyncValue.loading());

  final BookingsRepository _repo;

  Future<void> load(String vendorId) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => _repo.fetchVendorBookings(vendorId),
    );
  }

  Future<void> updateStatus(String bookingId, String status) async {}
}

final bookingsNotifierProvider =
    StateNotifierProvider<BookingsNotifier, AsyncValue<List<Booking>>>(
  (ref) => BookingsNotifier(ref.watch(bookingsRepositoryProvider)),
);

final bookingDetailProvider =
    FutureProvider.family<Booking, String>((ref, bookingId) {
  return ref.watch(bookingsRepositoryProvider).fetchBookingById(bookingId);
});
