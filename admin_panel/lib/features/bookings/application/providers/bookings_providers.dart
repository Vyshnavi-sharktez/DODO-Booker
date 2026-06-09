import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../auth/application/providers/auth_provider.dart';
import '../../data/bookings_repository.dart';
import '../../domain/models/booking.dart';

final bookingsRepositoryProvider = Provider<BookingsRepository>((ref) {
  return BookingsRepository(ref.watch(supabaseClientProvider));
});

class BookingsNotifier extends StateNotifier<AsyncValue<List<Booking>>> {
  final BookingsRepository _repo;

  BookingsNotifier(this._repo) : super(const AsyncValue.loading()) {
    _load();
  }

  Future<void> _load() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_repo.fetchBookings);
  }

  Future<void> refresh() => _load();

  Future<void> updateBooking(
    String id, {
    required String vendorId,
    required DateTime serviceDate,
    required String status,
    String? notes,
  }) async {
    final updated = await _repo.updateBooking(
      id,
      vendorId: vendorId,
      serviceDate: serviceDate,
      status: status,
      notes: notes,
    );
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncValue.data(
        current.map((b) => b.id == id ? updated : b).toList(),
      );
    }
  }

  Future<void> deleteBooking(String id) async {
    await _repo.deleteBooking(id);
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncValue.data(current.where((b) => b.id != id).toList());
    }
  }
}

final bookingsNotifierProvider =
    StateNotifierProvider<BookingsNotifier, AsyncValue<List<Booking>>>((ref) {
  return BookingsNotifier(ref.watch(bookingsRepositoryProvider));
});
