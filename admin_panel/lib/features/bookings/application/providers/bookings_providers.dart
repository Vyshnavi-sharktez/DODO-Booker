import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../auth/application/providers/auth_provider.dart';
import '../../data/bookings_repository.dart';
import '../../domain/models/booking.dart';

final bookingImagesProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, bookingId) async {
  final client = ref.watch(supabaseClientProvider);
  final rows = await client
      .from('booking_images')
      .select('image_type, image_url, created_at')
      .eq('booking_id', bookingId)
      .order('created_at');
  return List<Map<String, dynamic>>.from(rows as List);
});

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
        current.map((b) {
          if (b.id != id) return b;
          // Preserve existing addons — the repo mutation doesn't re-fetch them.
          return updated.copyWith(addons: b.addons);
        }).toList(),
      );
    }
  }

  Future<void> cancelBooking(String id) async {
    final updated = await _repo.cancelBooking(id);
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncValue.data(
        current.map((b) {
          if (b.id != id) return b;
          return updated.copyWith(addons: b.addons);
        }).toList(),
      );
    }
  }

  Future<void> createBooking({
    required String customerId,
    required DateTime serviceDate,
    required String address,
    String? notes,
    required List<({String serviceId, int quantity, double unitPrice})> items,
    List<({String addonId, String addonName, double addonPrice})> addons = const [],
  }) async {
    final created = await _repo.createBooking(
      customerId: customerId,
      serviceDate: serviceDate,
      address: address,
      notes: notes,
      items: items,
      addons: addons,
    );
    final current = state.valueOrNull ?? [];
    state = AsyncValue.data([created, ...current]);
  }

  Future<void> startDodoTeamService(String id) async {
    final updated = await _repo.startDodoTeamService(id);
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncValue.data(
        current.map((b) {
          if (b.id != id) return b;
          return updated.copyWith(addons: b.addons);
        }).toList(),
      );
    }
  }

  Future<void> completeDodoTeamBooking(String id, String otp) async {
    final updated = await _repo.completeDodoTeamBooking(id, otp);
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncValue.data(
        current.map((b) {
          if (b.id != id) return b;
          return updated.copyWith(addons: b.addons);
        }).toList(),
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
