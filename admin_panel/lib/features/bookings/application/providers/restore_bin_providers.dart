import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../auth/application/providers/auth_provider.dart';
import '../../data/restore_bin_repository.dart';
import '../../domain/models/deleted_booking.dart';

// ── Repository provider ───────────────────────────────────────────────────────

final restoreBinRepositoryProvider = Provider<RestoreBinRepository>((ref) {
  return RestoreBinRepository(ref.watch(supabaseClientProvider));
});

// ── Retention settings ────────────────────────────────────────────────────────

final retentionSettingsProvider =
    FutureProvider.autoDispose<({int value, String unit})>((ref) async {
  return ref.watch(restoreBinRepositoryProvider).fetchRetentionSettings();
});

// ── Deleted bookings list ─────────────────────────────────────────────────────

class DeletedBookingsNotifier
    extends StateNotifier<AsyncValue<List<DeletedBooking>>> {
  final RestoreBinRepository _repo;

  DeletedBookingsNotifier(this._repo) : super(const AsyncValue.loading()) {
    _load();
  }

  Future<void> _load() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_repo.fetchDeletedBookings);
  }

  Future<void> refresh() async {
    try {
      final fetched = await _repo.fetchDeletedBookings();
      state = AsyncValue.data(fetched);
    } catch (e, st) {
      debugPrint('[RestoreBin] refresh error: $e\n$st');
    }
  }

  // Returns the booking number on success, throws on failure.
  Future<String> restore(String bookingId) async {
    final result = await _repo.restoreBooking(bookingId);
    final bookingNumber = result['booking_number'] as String? ?? bookingId;
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncValue.data(
        current.where((b) => b.bookingId != bookingId).toList(),
      );
    }
    return bookingNumber;
  }

  // Returns purge result map.
  Future<Map<String, dynamic>> purgeExpired() async {
    final result = await _repo.purgeExpiredBookings();
    await refresh();
    return result;
  }
}

final deletedBookingsNotifierProvider = StateNotifierProvider<
    DeletedBookingsNotifier, AsyncValue<List<DeletedBooking>>>((ref) {
  return DeletedBookingsNotifier(ref.watch(restoreBinRepositoryProvider));
});
