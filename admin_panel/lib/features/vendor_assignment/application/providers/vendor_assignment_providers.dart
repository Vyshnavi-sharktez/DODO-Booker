import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../bookings/application/providers/bookings_providers.dart';
import '../../../vendors/application/providers/vendors_providers.dart';
import '../../../vendors/domain/models/vendor.dart';
import '../../domain/models/assignment_entry.dart';

// ── In-memory assignment history ──────────────────────────────────────────────

class VendorAssignmentHistoryNotifier
    extends StateNotifier<List<AssignmentEntry>> {
  VendorAssignmentHistoryNotifier() : super([]);

  void addEntry(AssignmentEntry entry) {
    state = [entry, ...state];
  }

  List<AssignmentEntry> forBooking(String bookingId) {
    return state.where((e) => e.bookingId == bookingId).toList();
  }
}

final vendorAssignmentHistoryProvider = StateNotifierProvider<
    VendorAssignmentHistoryNotifier, List<AssignmentEntry>>(
  (ref) => VendorAssignmentHistoryNotifier(),
);

// ── Active vendors only (for vendor picker) ───────────────────────────────────

final activeVendorsProvider = Provider<List<Vendor>>((ref) {
  final vendors = ref.watch(vendorsNotifierProvider).valueOrNull ?? [];
  return vendors.where((v) => v.isActive).toList();
});

// ── Booking status counts ─────────────────────────────────────────────────────

final unassignedBookingsCountProvider = Provider<int>((ref) {
  final bookings = ref.watch(bookingsNotifierProvider).valueOrNull ?? [];
  return bookings.where((b) => b.status == 'pending').length;
});

final assignedBookingsCountProvider = Provider<int>((ref) {
  final bookings = ref.watch(bookingsNotifierProvider).valueOrNull ?? [];
  return bookings.where((b) => b.status == 'assigned').length;
});

final inProgressBookingsCountProvider = Provider<int>((ref) {
  final bookings = ref.watch(bookingsNotifierProvider).valueOrNull ?? [];
  return bookings.where((b) => b.status == 'in_progress').length;
});

final rejectedBookingsCountProvider = Provider<int>((ref) {
  final bookings = ref.watch(bookingsNotifierProvider).valueOrNull ?? [];
  return bookings.where((b) => b.status == 'rejected').length;
});
