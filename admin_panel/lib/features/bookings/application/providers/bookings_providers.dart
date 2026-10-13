import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../auth/application/providers/auth_provider.dart';
import '../../data/bookings_repository.dart';
import '../../domain/models/booking.dart';

final bookingImagesProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, bookingId) async {
  final client = ref.watch(supabaseClientProvider);
  final rows = await client
      .from('booking_images')
      .select('image_type, image_url, media_type, created_at')
      .eq('booking_id', bookingId)
      .order('created_at');
  return List<Map<String, dynamic>>.from(rows as List);
});

class BookingPaymentAuditData {
  final List<Map<String, dynamic>> attempts;
  final String? refundStatus;
  final String? refundRequestId;
  final double? refundEligibleAmount;
  final String? refundTransactionId;
  final String? refundTransactionStatus;
  const BookingPaymentAuditData({
    required this.attempts,
    this.refundStatus,
    this.refundRequestId,
    this.refundEligibleAmount,
    this.refundTransactionId,
    this.refundTransactionStatus,
  });
}

final bookingPaymentAuditProvider = FutureProvider.autoDispose
    .family<BookingPaymentAuditData, String>((ref, bookingId) async {
  final client = ref.watch(supabaseClientProvider);

  final rows = await client
      .from('booking_payments')
      .select(
        'id, gateway, gateway_order_id, gateway_payment_id, '
        'amount, currency, status, failure_reason, attempt_number, created_at',
      )
      .eq('booking_id', bookingId)
      .order('attempt_number', ascending: false);

  final refundRow = await client
      .from('refund_requests')
      .select('id, status, approved_amount, refund_transactions(id, status)')
      .eq('booking_id', bookingId)
      .order('created_at', ascending: false)
      .limit(1)
      .maybeSingle();

  String? refundTransactionId;
  String? refundTransactionStatus;
  if (refundRow != null) {
    final txns = refundRow['refund_transactions'] as List?;
    if (txns != null && txns.isNotEmpty) {
      final latest = txns
          .map((t) => t as Map<String, dynamic>)
          .reduce((a, b) => (a['status'] as String?) == 'processing' ? a : b);
      refundTransactionId = latest['id'] as String?;
      refundTransactionStatus = latest['status'] as String?;
    }
  }

  return BookingPaymentAuditData(
    attempts: List<Map<String, dynamic>>.from(rows as List),
    refundStatus: refundRow?['status'] as String?,
    refundRequestId: refundRow?['id'] as String?,
    refundEligibleAmount:
        (refundRow?['approved_amount'] as num?)?.toDouble(),
    refundTransactionId: refundTransactionId,
    refundTransactionStatus: refundTransactionStatus,
  );
});

final bookingsRepositoryProvider = Provider<BookingsRepository>((ref) {
  return BookingsRepository(ref.watch(supabaseClientProvider));
});

class BookingsNotifier extends StateNotifier<AsyncValue<List<Booking>>> {
  final BookingsRepository _repo;

  // True while a create/edit mutation owns the state update.
  // Realtime-triggered refresh() calls are suppressed during this window
  // to prevent a concurrent fetch from overwriting the optimistic update
  // with a snapshot that was taken before all booking_items were inserted.
  bool _mutating = false;

  BookingsNotifier(this._repo) : super(const AsyncValue.loading()) {
    _load();
  }

  // Deduplicates a booking list by id, keeping the first occurrence.
  // Prevents duplicates that arise when both the optimistic update and a
  // concurrent realtime refresh insert the same booking into state.
  static List<Booking> _dedupe(List<Booking> list) {
    final seen = <String>{};
    return list.where((b) => seen.add(b.id)).toList();
  }

  Future<void> _load() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_repo.fetchBookings);
  }

  // Silent re-fetch: keeps existing data visible while re-querying.
  // The initial _load() still shows the spinner; refresh() does not.
  // Suppressed during active mutations to avoid overwriting an optimistic
  // update with a snapshot taken before booking_items were fully inserted.
  Future<void> refresh() async {
    if (_mutating) return;
    try {
      final fetched = await _repo.fetchBookings();
      if (!_mutating) state = AsyncValue.data(_dedupe(fetched));
    } catch (e, st) {
      // Keep existing state on background refresh errors — don't flash error.
      debugPrint('[Bookings] refresh error: $e\n$st');
    }
  }

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

  Future<void> updateBookingAddress(
    String id,
    String address, {
    double? latitude,
    double? longitude,
  }) async {
    final updated = await _repo.updateBookingAddress(
      id,
      address,
      latitude: latitude,
      longitude: longitude,
    );
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

  Future<void> updateBookingStatus(String id, String newStatus) async {
    final updated = await _repo.updateBookingStatus(id, newStatus);
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

  Future<void> cancelBooking(String id, {String? reason}) async {
    final updated = await _repo.cancelBooking(id, reason: reason);
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
    String? scheduledTime,
    double? latitude,
    double? longitude,
    required List<({String serviceId, String? customName, String? customCategoryName, int quantity, double unitPrice})> items,
    List<({String addonId, String addonName, double addonPrice})> addons = const [],
    double discountAmount = 0.0,
    double taxAmount = 0.0,
    String? couponCode,
  }) async {
    _mutating = true;
    try {
      final created = await _repo.createBooking(
        customerId: customerId,
        serviceDate: serviceDate,
        address: address,
        notes: notes,
        scheduledTime: scheduledTime,
        latitude: latitude,
        longitude: longitude,
        items: items,
        addons: addons,
        discountAmount: discountAmount,
        taxAmount: taxAmount,
        couponCode: couponCode,
      );
      final current = state.valueOrNull ?? [];
      state = AsyncValue.data(_dedupe([created, ...current]));
    } finally {
      _mutating = false;
      // After mutation completes, do a real refresh so booking_items are fully
      // loaded (realtime events during _mutating=true were suppressed).
      unawaited(refresh());
    }
  }

  Future<void> updateBookingFull({
    required String id,
    required DateTime serviceDate,
    required String address,
    required String status,
    String? notes,
    String? scheduledTime,
    double? latitude,
    double? longitude,
    required List<({String serviceId, String? customName, String? customCategoryName, int quantity, double unitPrice})> items,
    List<({String addonId, String addonName, double addonPrice})> addons = const [],
    double discountAmount = 0.0,
    double taxAmount = 0.0,
    String? couponCode,
  }) async {
    _mutating = true;
    try {
      final updated = await _repo.updateBookingFull(
        id: id,
        serviceDate: serviceDate,
        address: address,
        status: status,
        notes: notes,
        scheduledTime: scheduledTime,
        latitude: latitude,
        longitude: longitude,
        items: items,
        addons: addons,
        discountAmount: discountAmount,
        taxAmount: taxAmount,
        couponCode: couponCode,
      );
      final current = state.valueOrNull;
      if (current != null) {
        state = AsyncValue.data(
          current.map((b) => b.id == id ? updated : b).toList(),
        );
      }
    } finally {
      _mutating = false;
      unawaited(refresh());
    }
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
