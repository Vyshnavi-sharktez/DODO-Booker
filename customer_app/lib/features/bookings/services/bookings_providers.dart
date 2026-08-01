import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'bookings_service.dart';
import '../../../models/my_booking_model.dart';
import '../../amc/models/amc_contract_summary.dart';

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

final bookingImagesProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, bookingId) async {
  final rows = await Supabase.instance.client
      .from('booking_images')
      .select('image_type, image_url, created_at')
      .eq('booking_id', bookingId)
      .order('created_at');
  return List<Map<String, dynamic>>.from(rows as List);
});

// ── Processed bookings: separates regular bookings from AMC contracts ──────────

class ProcessedBookings {
  final List<MyBookingModel> regular;
  final List<AmcContractSummary> amcContracts;

  const ProcessedBookings({
    required this.regular,
    required this.amcContracts,
  });
}

final processedBookingsProvider =
    FutureProvider<ProcessedBookings>((ref) async {
  final bookings = await ref.watch(myBookingsProvider.future);

  final regular = bookings.where((b) => !b.isAmc).toList();
  final amcBookings = bookings
      .where((b) => b.isAmc && b.amcContractId != null)
      .toList();

  if (amcBookings.isEmpty) {
    return ProcessedBookings(regular: regular, amcContracts: []);
  }

  // Group AMC visit bookings by contract ID.
  final grouped = <String, List<MyBookingModel>>{};
  for (final b in amcBookings) {
    grouped.putIfAbsent(b.amcContractId!, () => []).add(b);
  }

  // Batch-fetch authoritative contract metadata (status, visits_completed,
  // total visits) so the summary card always reflects the server truth.
  final contractIds = grouped.keys.toList();
  final client = Supabase.instance.client;
  final rows = await client
      .from('amc_contracts')
      .select(
        'id, status, visits_completed, num_visits, total_visits, '
        'service_id, service_name, plan_name, created_at, '
        'amc_plan_id, price_per_visit, recurrence_interval, '
        'package_duration, service_interval, '
        'original_total, discount_type, discount_value, discount_amount, final_price, '
        'quantity',
      )
      .inFilter('id', contractIds);

  final amcContracts = (rows as List).map((row) {
    final m = Map<String, dynamic>.from(row as Map);
    final id = m['id'] as String;
    return AmcContractSummary(
      contractId: id,
      serviceId: m['service_id'] as String? ?? '',
      serviceName: m['service_name'] as String? ?? '',
      planName: m['plan_name'] as String? ?? '',
      contractStatus: m['status'] as String? ?? 'active',
      totalVisits: ((m['num_visits'] as num?)?.toInt()) ??
          (m['total_visits'] as num?)?.toInt() ??
          0,
      visitsCompleted: (m['visits_completed'] as num?)?.toInt() ?? 0,
      visitBookings: grouped[id] ?? [],
      createdAt: DateTime.parse(m['created_at'] as String),
      amcPlanId: m['amc_plan_id'] as String?,
      pricePerVisit: (m['price_per_visit'] as num?)?.toDouble() ?? 0.0,
      recurrenceInterval: m['recurrence_interval'] as String? ?? '',
      packageDuration: m['package_duration'] as String?,
      serviceInterval: m['service_interval'] as String?,
      numVisits: (m['num_visits'] as num?)?.toInt(),
      originalTotal: (m['original_total'] as num?)?.toDouble(),
      discountType: m['discount_type'] as String?,
      discountValue: (m['discount_value'] as num?)?.toDouble(),
      discountAmount: (m['discount_amount'] as num?)?.toDouble(),
      finalPrice: (m['final_price'] as num?)?.toDouble(),
      quantity: (m['quantity'] as num?)?.toInt() ?? 1,
    );
  }).toList();

  return ProcessedBookings(regular: regular, amcContracts: amcContracts);
});
