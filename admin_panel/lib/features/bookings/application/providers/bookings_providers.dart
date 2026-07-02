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

  Future<void> updateBookingAssignment(
    String id, {
    required String assignmentType,
    String? vendorId,
    String? dodoTeamId,
    required DateTime serviceDate,
    String? notes,
  }) async {
    final updated = await _repo.updateBookingAssignment(
      id,
      assignmentType: assignmentType,
      vendorId: vendorId,
      dodoTeamId: dodoTeamId,
      serviceDate: serviceDate,
      notes: notes,
    );
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncValue.data(
        current.map((b) => b.id == id ? updated : b).toList(),
      );
    }
  }

  Future<void> cancelBooking(String id) async {
    final updated = await _repo.cancelBooking(id);
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncValue.data(
        current.map((b) => b.id == id ? updated : b).toList(),
      );
    }
  }

  Future<void> createBooking({
    required String customerId,
    required DateTime serviceDate,
    required String address,
    String? notes,
    required List<({String serviceId, int quantity, double unitPrice})> items,
  }) async {
    final created = await _repo.createBooking(
      customerId: customerId,
      serviceDate: serviceDate,
      address: address,
      notes: notes,
      items: items,
    );
    final current = state.valueOrNull ?? [];
    state = AsyncValue.data([created, ...current]);
  }

  Future<void> startDodoTeamService(String id) async {
    final updated = await _repo.startDodoTeamService(id);
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncValue.data(
        current.map((b) => b.id == id ? updated : b).toList(),
      );
    }
  }

  Future<void> completeDodoTeamBooking(String id, String otp) async {
    final updated = await _repo.completeDodoTeamBooking(id, otp);

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
