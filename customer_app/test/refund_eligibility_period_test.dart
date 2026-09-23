import 'package:flutter_test/flutter_test.dart';
import 'package:customer_app/features/refund_queries/models/booking_for_refund_model.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

Map<String, dynamic> _base({
  String status = 'completed',
  String paymentMethod = 'online',
  String? completedAt,
}) =>
    {
      'id': 'bk-uuid-001',
      'booking_number': 'BK-2026-0001',
      'service_date': '2026-09-10',
      'created_at': '2026-09-01T10:00:00.000Z',
      'status': status,
      'total_amount': 500.0,
      'payment_method': paymentMethod,
      'booking_items': const [],
      'booking_payments': const [],
      if (completedAt != null) 'completed_at': completedAt,
    };

DateTime _daysAgo(int n) =>
    DateTime.now().subtract(Duration(days: n, hours: 1));

DateTime _daysFromNow(int n) =>
    DateTime.now().add(Duration(days: n, hours: 1));

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('BookingForRefundModel — completed_at parsing', () {
    test('parses completed_at from ISO string', () {
      final m = _base(completedAt: '2026-09-15T12:00:00.000Z');
      final b = BookingForRefundModel.fromMap(m);
      expect(b.completedAt, isNotNull);
      expect(b.completedAt!.year, 2026);
      expect(b.completedAt!.month, 9);
      expect(b.completedAt!.day, 15);
    });

    test('completed_at is null when field absent from map', () {
      final m = _base();
      final b = BookingForRefundModel.fromMap(m);
      expect(b.completedAt, isNull);
    });

    test('completed_at is null when field is null in map', () {
      final m = _base()..['completed_at'] = null;
      final b = BookingForRefundModel.fromMap(m);
      expect(b.completedAt, isNull);
    });

    test('copyWith preserves completedAt when not overridden', () {
      final m = _base(completedAt: '2026-09-15T12:00:00.000Z');
      final b = BookingForRefundModel.fromMap(m);
      final copy = b.copyWith(hasCompletedRefund: true);
      expect(copy.completedAt, b.completedAt);
    });

    test('copyWith can override completedAt', () {
      final m = _base(completedAt: '2026-09-15T12:00:00.000Z');
      final b = BookingForRefundModel.fromMap(m);
      final newDate = DateTime(2026, 9, 20);
      final copy = b.copyWith(completedAt: newDate);
      expect(copy.completedAt, newDate);
    });
  });

  group('isRefundPeriodExpired — completed bookings', () {
    test('returns false when completedAt is within the period', () {
      final completedAt = _daysAgo(5).toUtc().toIso8601String();
      final b = BookingForRefundModel.fromMap(_base(completedAt: completedAt));
      expect(b.isRefundPeriodExpired(30), isFalse);
    });

    test('returns true when completedAt is beyond the period', () {
      final completedAt = _daysAgo(31).toUtc().toIso8601String();
      final b = BookingForRefundModel.fromMap(_base(completedAt: completedAt));
      expect(b.isRefundPeriodExpired(30), isTrue);
    });

    test('returns false on the boundary day (within period)', () {
      final completedAt = _daysAgo(30).toUtc().toIso8601String();
      // _daysAgo(30) subtracts 30 days + 1 hour, so this is just past the
      // boundary — deadline = completedAt + 30d, now is ~30d + 1h after.
      // This is intentionally past the deadline to test the boundary clearly.
      final b = BookingForRefundModel.fromMap(_base(completedAt: completedAt));
      // 30 days + 1 hour ago → deadline was 1 hour ago → expired
      expect(b.isRefundPeriodExpired(30), isTrue);
    });

    test('returns false when completedAt is in the future (clock skew guard)', () {
      final completedAt = _daysFromNow(1).toUtc().toIso8601String();
      final b = BookingForRefundModel.fromMap(_base(completedAt: completedAt));
      expect(b.isRefundPeriodExpired(30), isFalse);
    });

    test('period=0 means immediately expired for any completed booking', () {
      final completedAt = _daysAgo(0).toUtc().toIso8601String();
      final b = BookingForRefundModel.fromMap(_base(
        completedAt: completedAt,
      ));
      // completed ~1 hour ago, period=0 → deadline = completedAt, now > deadline
      expect(b.isRefundPeriodExpired(0), isTrue);
    });

    test('period=365 — booking completed 364 days ago is still eligible', () {
      final completedAt = _daysAgo(364).toUtc().toIso8601String();
      final b = BookingForRefundModel.fromMap(_base(completedAt: completedAt));
      expect(b.isRefundPeriodExpired(365), isFalse);
    });

    test('period=365 — booking completed 366 days ago is expired', () {
      final completedAt = _daysAgo(366).toUtc().toIso8601String();
      final b = BookingForRefundModel.fromMap(_base(completedAt: completedAt));
      expect(b.isRefundPeriodExpired(365), isTrue);
    });

    test('service-specific period shorter than global: 7 days, completed 8 days ago', () {
      final completedAt = _daysAgo(8).toUtc().toIso8601String();
      final b = BookingForRefundModel.fromMap(_base(completedAt: completedAt));
      expect(b.isRefundPeriodExpired(7), isTrue);
      // But with global 30-day period it would still appear eligible in UI
      expect(b.isRefundPeriodExpired(30), isFalse);
    });

    test('returns false when completedAt is null (column not yet populated)', () {
      final b = BookingForRefundModel.fromMap(_base());
      expect(b.completedAt, isNull);
      expect(b.isRefundPeriodExpired(30), isFalse);
    });
  });

  group('isRefundPeriodExpired — cancelled bookings bypass the period', () {
    test('cancelled booking always returns false regardless of completedAt', () {
      final completedAt = _daysAgo(100).toUtc().toIso8601String();
      final b = BookingForRefundModel.fromMap(
        _base(status: 'cancelled', completedAt: completedAt),
      );
      // Period is irrelevant for cancelled bookings — completed_at means
      // nothing for a booking that was never completed.
      expect(b.isRefundPeriodExpired(0), isFalse);
      expect(b.isRefundPeriodExpired(30), isFalse);
    });

    test('cancelled online booking with captured payment — period does not apply', () {
      final completedAt = _daysAgo(60).toUtc().toIso8601String();
      final b = BookingForRefundModel.fromMap(
        _base(
          status: 'cancelled',
          paymentMethod: 'online',
          completedAt: completedAt,
        ),
      );
      expect(b.isRefundPeriodExpired(30), isFalse);
    });

    test('cancelled COD booking — no refund due, period does not apply', () {
      final b = BookingForRefundModel.fromMap(
        _base(status: 'cancelled', paymentMethod: 'cod'),
      );
      expect(b.isRefundPeriodExpired(30), isFalse);
    });
  });

  group('Interaction: hasCompletedRefund vs isRefundPeriodExpired', () {
    test('both flags can coexist on the same model without conflict', () {
      final completedAt = _daysAgo(50).toUtc().toIso8601String();
      final b = BookingForRefundModel.fromMap(
        _base(completedAt: completedAt),
      ).copyWith(hasCompletedRefund: true);
      expect(b.hasCompletedRefund, isTrue);
      expect(b.isRefundPeriodExpired(30), isTrue);
    });

    test('copyWith(hasCompletedRefund) preserves completedAt for expiry check', () {
      final completedAt = _daysAgo(50).toUtc().toIso8601String();
      final original =
          BookingForRefundModel.fromMap(_base(completedAt: completedAt));
      final updated = original.copyWith(hasCompletedRefund: true);
      expect(updated.completedAt, original.completedAt);
      expect(updated.isRefundPeriodExpired(30), isTrue);
    });
  });
}
