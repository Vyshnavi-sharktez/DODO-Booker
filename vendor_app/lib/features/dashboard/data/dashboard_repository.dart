import 'package:flutter/foundation.dart';
import '../../../shared/repositories/base_repository.dart';
import '../domain/models/dashboard_stats.dart';

class DashboardRepository extends BaseRepository {
  const DashboardRepository(super.supabase);

  static const _select =
      'id, booking_number, status, total_amount, service_date, notes, created_at';

  Future<DashboardStats> fetchStats(String vendorId) async {
    debugPrint('[DASH][Repo] fetchStats — vendorId=$vendorId');
    try {
      final rows = await supabase
          .from('bookings')
          .select(_select)
          .eq('vendor_id', vendorId)
          .order('created_at', ascending: false);

      final bookings = List<Map<String, dynamic>>.from(rows as List);
      debugPrint('[DASH][Repo] query returned ${bookings.length} rows');

      final todayDate = _todayDate();
      final tomorrow = todayDate.add(const Duration(days: 1));
      final weekStart = _weekStart();
      final monthStart = _monthStart();

      int assigned = 0, inProgress = 0, completed = 0, rejected = 0;
      int todayCount = 0, totalForRates = 0;
      double totalEarnings = 0.0;
      double todayEarnings = 0.0;
      double weeklyEarnings = 0.0;
      double monthlyEarnings = 0.0;

      final upcoming = <DashboardBooking>[];

      for (final b in bookings) {
        final status = b['status'] as String? ?? '';
        final amount = (b['total_amount'] as num?)?.toDouble() ?? 0.0;
        final rawDate = b['service_date'] as String?;
        final serviceDt = rawDate != null ? DateTime.tryParse(rawDate) : null;
        // Normalise to midnight for date-only comparisons
        final serviceDay = serviceDt != null
            ? DateTime(serviceDt.year, serviceDt.month, serviceDt.day)
            : null;

        // ── Status counts ────────────────────────────────────────────────────
        switch (status) {
          case 'assigned':
            assigned++;
            totalForRates++;
          case 'in_progress':
            inProgress++;
            totalForRates++;
          case 'completed':
            completed++;
            totalForRates++;
            totalEarnings += amount;
            // Period earnings keyed on service_date
            if (serviceDay != null) {
              if (!serviceDay.isBefore(todayDate) && serviceDay.isBefore(tomorrow)) {
                todayEarnings += amount;
              }
              if (!serviceDay.isBefore(weekStart)) weeklyEarnings += amount;
              if (!serviceDay.isBefore(monthStart)) monthlyEarnings += amount;
            }
          case 'rejected':
            rejected++;
            totalForRates++;
          case 'cancelled':
            totalForRates++;
        }

        // ── Today's booking count (all statuses) ────────────────────────────
        if (serviceDay != null &&
            !serviceDay.isBefore(todayDate) &&
            serviceDay.isBefore(tomorrow)) {
          todayCount++;
        }

        // ── Upcoming schedule: active bookings on or after today ─────────────
        if ((status == 'assigned' || status == 'in_progress') &&
            serviceDay != null &&
            !serviceDay.isBefore(todayDate)) {
          upcoming.add(_toBooking(b, serviceDt));
        }
      }

      // Sort upcoming ascending by service_date; take first 5
      upcoming.sort((a, b) => (a.serviceDate ?? DateTime(9999))
          .compareTo(b.serviceDate ?? DateTime(9999)));

      final completionRate =
          totalForRates > 0 ? (completed / totalForRates * 100) : 0.0;
      final rejectionRate =
          totalForRates > 0 ? (rejected / totalForRates * 100) : 0.0;

      // Recent activity: top 5 by created_at (already sorted DESC from query)
      final recent = bookings.take(5).map((b) {
        final rawDate = b['service_date'] as String?;
        return _toBooking(
            b, rawDate != null ? DateTime.tryParse(rawDate) : null);
      }).toList();

      return DashboardStats(
        assignedCount: assigned,
        inProgressCount: inProgress,
        completedCount: completed,
        rejectedCount: rejected,
        todayCount: todayCount,
        totalEarnings: totalEarnings,
        todayEarnings: todayEarnings,
        weeklyEarnings: weeklyEarnings,
        monthlyEarnings: monthlyEarnings,
        completionRate: completionRate,
        rejectionRate: rejectionRate,
        recentBookings: recent,
        upcomingBookings: upcoming.take(5).toList(),
      );
    } catch (e, st) {
      debugPrint('[DASH][Repo] ERROR: $e');
      debugPrint('[DASH][Repo] STACKTRACE: $st');
      rethrow;
    }
  }

  static DashboardBooking _toBooking(
      Map<String, dynamic> b, DateTime? serviceDt) {
    return DashboardBooking(
      id: b['id'] as String,
      bookingNumber: b['booking_number'] as String? ?? '',
      service: (b['notes'] as String?)?.split(' · ').first,
      status: b['status'] as String? ?? '',
      amount: (b['total_amount'] as num?)?.toDouble() ?? 0.0,
      serviceDate: serviceDt,
      createdAt: b['created_at'] != null
          ? DateTime.tryParse(b['created_at'] as String)
          : null,
    );
  }

  // ── Date helpers ────────────────────────────────────────────────────────────

  static DateTime _todayDate() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  // ISO week: Monday = weekday 1
  static DateTime _weekStart() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day - (n.weekday - 1));
  }

  static DateTime _monthStart() {
    final n = DateTime.now();
    return DateTime(n.year, n.month); // day defaults to 1
  }
}
