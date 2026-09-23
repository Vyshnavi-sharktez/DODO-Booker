import 'package:flutter_test/flutter_test.dart';
import 'package:customer_app/features/refund_queries/models/booking_for_refund_model.dart';
import 'package:customer_app/models/my_booking_model.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

const _uuid = 'c86b1c92-aaaa-bbbb-cccc-000000000000';
const _expectedRef = 'BK-C86B1C92';

Map<String, dynamic> _refundBookingMap({String? bookingNumber}) => {
      'id': _uuid,
      'booking_number': bookingNumber,
      'service_date': '2026-09-10',
      'created_at': '2026-09-01T10:00:00.000Z',
      'status': 'completed',
      'total_amount': 500.0,
      'payment_method': 'online',
      'booking_items': [
        {
          'catalog_nodes': {'id': 'cat-1', 'name': 'AC Service'},
          'vendor_service_requests': null,
        }
      ],
      'booking_payments': [
        {'id': 'pay-001', 'status': 'success'},
      ],
    };

Map<String, dynamic> _myBookingMap({String? bookingNumber}) => {
      'id': _uuid,
      'booking_number': bookingNumber,
      'customer_id': 'cust-001',
      'service_id': 'svc-001',
      'service_name': 'AC Service',
      'category_name': 'AC',
      'category_icon_key': 'ac',
      'subcategory_name': null,
      'items': <dynamic>[],
      'addons': <dynamic>[],
      // Plain-text address: parsed by _parseTextAddress in MyBookingModel.fromJson.
      'address': '123 Main St, Hyderabad, Telangana, 500001',
      'service_date': '2026-09-10T09:00:00.000Z',
      'scheduled_date': '2026-09-10T09:00:00.000Z',
      'time_slot': '09:00 AM',
      'base_amount': 450.0,
      'tax_amount': 50.0,
      'total_amount': 500.0,
      'status': 'completed',
      'assignment_type': 'External Vendor',
      'payment_method': 'online',
      'payment_status': 'success',
      'created_at': '2026-09-01T10:00:00.000Z',
      'updated_at': '2026-09-01T10:00:00.000Z',
      'vendor_id': null,
      'vendor_name': null,
      'vendor_phone': null,
      'completion_otp': null,
      'booking_timeline': <dynamic>[],
      'review': null,
      'has_review': false,
      'can_review': false,
    };

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('Booking reference — cross-model consistency', () {
    test('BookingForRefundModel: null booking_number → BK-{first8ofId}', () {
      final b = BookingForRefundModel.fromMap(_refundBookingMap());
      expect(b.displayBookingNumber, _expectedRef);
    });

    test('MyBookingModel: null booking_number → BK-{first8ofId}', () {
      final b = MyBookingModel.fromJson(_myBookingMap());
      expect(b.displayBookingNumber, _expectedRef);
    });

    test('both models produce identical reference for the same booking UUID', () {
      final refund = BookingForRefundModel.fromMap(_refundBookingMap());
      final my = MyBookingModel.fromJson(_myBookingMap());
      expect(refund.displayBookingNumber, equals(my.displayBookingNumber));
    });

    test('stored booking_number used by both models when present', () {
      const stored = 'BK-CUSTOM99';
      final refund =
          BookingForRefundModel.fromMap(_refundBookingMap(bookingNumber: stored));
      final my = MyBookingModel.fromJson(_myBookingMap(bookingNumber: stored));
      expect(refund.displayBookingNumber, stored);
      expect(my.displayBookingNumber, stored);
    });

    test('backfill value matches client-generated fallback — no visible change', () {
      // Migration 20260923000007 writes: 'BK-' || UPPER(LEFT(id::text, 8))
      // Simulate what the migration writes:
      final backfilled = 'BK-${_uuid.substring(0, 8).toUpperCase()}';

      // With null (pre-migration): client generates same value.
      final preBackfill = BookingForRefundModel.fromMap(_refundBookingMap());
      // With stored value (post-migration): model uses DB value.
      final postBackfill = BookingForRefundModel.fromMap(
          _refundBookingMap(bookingNumber: backfilled));

      expect(preBackfill.displayBookingNumber, _expectedRef);
      expect(postBackfill.displayBookingNumber, _expectedRef);
      expect(preBackfill.displayBookingNumber,
          equals(postBackfill.displayBookingNumber));
    });

    test('reference never exposes the raw UUID to the customer', () {
      final b = BookingForRefundModel.fromMap(_refundBookingMap());
      expect(b.displayBookingNumber, isNot(equals(_uuid)));
      expect(b.displayBookingNumber, isNot(contains('-aaaa-')));
    });

    test('reference always starts with BK-', () {
      final b = BookingForRefundModel.fromMap(_refundBookingMap());
      final m = MyBookingModel.fromJson(_myBookingMap());
      expect(b.displayBookingNumber, startsWith('BK-'));
      expect(m.displayBookingNumber, startsWith('BK-'));
    });
  });

  group('Admin search — last-5-chars lookup logic', () {
    // The admin dialog hint says "last 5 digits of booking number".
    // The customer reads e.g. BK-C86B1C92 → tells admin "B1C92".
    // Admin enters "B1C92" → repository searches id::text ILIKE '%B1C92%'.
    // This group verifies the string relationship that makes that work.

    test('last 5 chars of BK suffix appear in the raw UUID', () {
      final ref = _expectedRef; // 'BK-C86B1C92'
      final suffix = ref.substring(3); // 'C86B1C92'
      final last5 = suffix.substring(suffix.length - 5); // 'B1C92'
      expect(_uuid.toUpperCase().contains(last5), isTrue);
    });

    test('stripping BK- prefix from query gives id search term', () {
      const query = 'BK-C86B1C92';
      final idQuery =
          query.toUpperCase().startsWith('BK-') ? query.substring(3) : query;
      expect(_uuid.toUpperCase().contains(idQuery), isTrue);
    });

    test('partial query (last 5) still matches UUID', () {
      const last5 = 'B1C92';
      expect(_uuid.toUpperCase().contains(last5), isTrue);
    });

    test('after backfill, booking_number search also finds booking', () {
      final backfilled = 'BK-${_uuid.substring(0, 8).toUpperCase()}';
      const last5 = 'B1C92';
      // Path A (booking_number ILIKE '%B1C92%') will match after migration.
      expect(backfilled.contains(last5), isTrue);
    });
  });
}
