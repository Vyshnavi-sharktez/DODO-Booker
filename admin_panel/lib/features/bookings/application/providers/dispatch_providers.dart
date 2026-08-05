import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/bookings_repository.dart';
import '../../domain/models/booking_assignment_record.dart';
import '../../domain/models/dispatch_settings.dart';
import 'bookings_providers.dart';
import 'dart:async';
class DispatchSettingsNotifier extends StateNotifier<AsyncValue<DispatchSettings>> {
  final BookingsRepository _repository;

  DispatchSettingsNotifier(this._repository) : super(const AsyncValue.loading()) {
    fetchSettings();
  }

  Future<void> fetchSettings() async {
    state = const AsyncValue.loading();
    try {
      final settings = await _repository.fetchDispatchSettings();
      state = AsyncValue.data(settings);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> updateSettings(DispatchSettings newSettings) async {
    try {
      final updated = await _repository.updateDispatchSettings(newSettings);
      state = AsyncValue.data(updated);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

final dispatchSettingsNotifierProvider = StateNotifierProvider<
    DispatchSettingsNotifier, AsyncValue<DispatchSettings>>((ref) {
  return DispatchSettingsNotifier(ref.watch(bookingsRepositoryProvider));
});

final bookingAssignmentsHistoryProvider = FutureProvider.autoDispose
    .family<List<BookingAssignmentRecord>, String>((ref, bookingId) {
  return ref
      .watch(bookingsRepositoryProvider)
      .fetchBookingAssignmentsHistory(bookingId);
});

final allBookingAssignmentsHistoryProvider =
    FutureProvider.autoDispose<List<BookingAssignmentRecord>>((ref) {
  return ref
      .watch(bookingsRepositoryProvider)
      .fetchAllBookingAssignmentsHistory();
});

final dispatchEscalationTimerProvider = Provider<void>((ref) {
  final repo = ref.watch(bookingsRepositoryProvider);
  final timer = Timer.periodic(const Duration(seconds: 10), (_) async {
    try {
      final count = await repo.processPendingDispatchEscalations();
      if (count > 0) {
        ref.read(bookingsNotifierProvider.notifier).refresh();
      }
    } catch (_) {}
  });

  ref.onDispose(timer.cancel);
});
