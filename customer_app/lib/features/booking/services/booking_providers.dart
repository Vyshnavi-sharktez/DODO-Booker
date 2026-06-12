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

// Key is ISO date string e.g. "2026-06-10"
final timeSlotsProvider = FutureProvider.family<List<TimeSlotModel>, String>(
  (ref, dateStr) => ref.read(bookingServiceProvider).fetchAvailableSlots(dateStr),
);
