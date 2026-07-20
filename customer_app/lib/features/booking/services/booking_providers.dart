import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'booking_service.dart';
import '../../../features/address/services/address_providers.dart';
import '../../../models/address_model.dart';
import '../../../models/time_slot_model.dart';

export '../../../features/address/services/address_providers.dart'
    show addressNotifierProvider, addressServiceProvider;

final bookingServiceProvider = Provider<BookingService>(
  (ref) => BookingService(),
);

// Alias: derives from addressNotifierProvider so address CRUD is reflected here.
final addressesProvider = Provider<AsyncValue<List<AddressModel>>>(
  (ref) => ref.watch(addressNotifierProvider),
);

// Key: (date, serviceId, parentNodeId?, vendorId?).
// parentNodeId drives scoped scheduling resolution; null falls back to global.
// vendorId filters capacity to only that vendor's bookings when set.
final timeSlotsProvider = FutureProvider.family<List<TimeSlotModel>,
    ({String date, String serviceId, String? parentNodeId, String? vendorId})>(
  (ref, key) => ref.read(bookingServiceProvider).fetchAvailableSlots(
        key.date,
        key.serviceId,
        parentNodeId: key.parentNodeId,
        vendorId: key.vendorId,
      ),
);

/// Holds the preferred vendor selected during the current booking session.
/// Reset to the default (no selection) before each new flow starts.
final selectedPreferredVendorProvider =
    StateProvider<({String? id, String? name, double fee})>(
  (_) => (id: null, name: null, fee: 0.0),
);
