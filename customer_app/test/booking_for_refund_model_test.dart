import 'package:flutter_test/flutter_test.dart';
import 'package:customer_app/features/refund_queries/models/booking_for_refund_model.dart';

Map<String, dynamic> _base({
  String id = 'bk-uuid-001',
  String bookingNumber = 'BK-2026-0001',
  String serviceDate = '2026-09-10',
  String status = 'completed',
  double totalAmount = 500.0,
  String paymentMethod = 'online',
  List<dynamic> bookingItems = const [],
  List<dynamic> bookingPayments = const [],
  String? notes,
}) =>
    {
      'id': id,
      'booking_number': bookingNumber,
      'service_date': serviceDate,
      'created_at': '2026-09-01T10:00:00.000Z',
      'status': status,
      'total_amount': totalAmount,
      'payment_method': paymentMethod,
      'booking_items': bookingItems,
      'booking_payments': bookingPayments,
      if (notes != null) 'notes': notes,
    };

Map<String, dynamic> _catalogItem(String name) => {
      'catalog_nodes': {'id': 'cat-1', 'name': name},
      'vendor_service_requests': null,
    };

Map<String, dynamic> _customItem(String serviceName) => {
      'catalog_nodes': null,
      'vendor_service_requests': {'id': 'vsr-1', 'service_name': serviceName},
    };

void main() {
  group('BookingForRefundModel.fromMap — basic parsing', () {
    test('parses id, booking number, status, amount, payment method', () {
      final m = _base(bookingItems: [_catalogItem('AC Repair')]);
      final b = BookingForRefundModel.fromMap(m);
      expect(b.id, 'bk-uuid-001');
      expect(b.bookingNumber, 'BK-2026-0001');
      expect(b.status, 'completed');
      expect(b.totalAmount, 500.0);
      expect(b.paymentMethod, 'online');
    });

    test('parses service_date into scheduledDate', () {
      final m = _base(serviceDate: '2026-09-10');
      final b = BookingForRefundModel.fromMap(m);
      expect(b.scheduledDate, DateTime(2026, 9, 10));
    });

    test('falls back to created_at when service_date is absent', () {
      final m = _base()..remove('service_date');
      final b = BookingForRefundModel.fromMap(m);
      expect(b.scheduledDate, DateTime.parse('2026-09-01T10:00:00.000Z'));
    });

    test('missing booking_number produces null (displayBookingNumber uses ID)', () {
      final m = _base()..['booking_number'] = null;
      final b = BookingForRefundModel.fromMap(m);
      expect(b.bookingNumber, isNull);
      expect(b.displayBookingNumber,
          startsWith('BK-${b.id.substring(0, 8).toUpperCase()}'));
    });

    test('total_amount zero is allowed', () {
      final m = _base(totalAmount: 0.0, bookingItems: [_catalogItem('Rework')]);
      final b = BookingForRefundModel.fromMap(m);
      expect(b.totalAmount, 0.0);
    });
  });

  group('BookingForRefundModel.fromMap — service name resolution', () {
    test('picks catalog_nodes name from first booking_item', () {
      final m = _base(bookingItems: [_catalogItem('AC Service')]);
      expect(BookingForRefundModel.fromMap(m).serviceName, 'AC Service');
    });

    test('falls back to vendor_service_requests name when catalog is null', () {
      final m = _base(bookingItems: [_customItem('Custom Plumbing')]);
      expect(BookingForRefundModel.fromMap(m).serviceName, 'Custom Plumbing');
    });

    test('appends "+ N more" when multiple items', () {
      final m = _base(bookingItems: [
        _catalogItem('AC Service'),
        _catalogItem('Fan Install'),
        _catalogItem('Light Fix'),
      ]);
      expect(
        BookingForRefundModel.fromMap(m).serviceName,
        'AC Service + 2 more',
      );
    });

    test('falls back to notes when booking_items is empty', () {
      final m = _base(notes: 'Deep Clean · special instructions');
      expect(BookingForRefundModel.fromMap(m).serviceName, 'Deep Clean');
    });

    test('uses "Service" sentinel when no name can be resolved', () {
      final m = _base();
      expect(BookingForRefundModel.fromMap(m).serviceName, 'Service');
    });
  });

  group('BookingForRefundModel.fromMap — payment method', () {
    test('online payment method parsed correctly', () {
      final m = _base(paymentMethod: 'online');
      expect(BookingForRefundModel.fromMap(m).paymentMethod, 'online');
      expect(BookingForRefundModel.fromMap(m).isOnlinePayment, isTrue);
      expect(BookingForRefundModel.fromMap(m).paymentMethodLabel, 'Online');
    });

    test('razorpay (legacy) treated as Online', () {
      final m = _base(paymentMethod: 'razorpay');
      expect(BookingForRefundModel.fromMap(m).paymentMethod, 'razorpay');
      expect(BookingForRefundModel.fromMap(m).isOnlinePayment, isTrue);
      expect(BookingForRefundModel.fromMap(m).paymentMethodLabel, 'Online');
    });

    test('cod payment method parsed correctly', () {
      final m = _base(paymentMethod: 'cod');
      expect(BookingForRefundModel.fromMap(m).paymentMethod, 'cod');
      expect(BookingForRefundModel.fromMap(m).isOnlinePayment, isFalse);
      expect(BookingForRefundModel.fromMap(m).paymentMethodLabel, 'COD');
    });

    test('cash payment method parsed correctly', () {
      final m = _base(paymentMethod: 'cash');
      expect(BookingForRefundModel.fromMap(m).paymentMethod, 'cash');
      expect(BookingForRefundModel.fromMap(m).isOnlinePayment, isFalse);
      expect(BookingForRefundModel.fromMap(m).paymentMethodLabel, 'COD');
    });

    test('missing payment_method defaults to cash', () {
      final m = _base()..remove('payment_method');
      expect(BookingForRefundModel.fromMap(m).paymentMethod, 'cash');
    });
  });

  group('BookingForRefundModel.fromMap — paymentId from booking_payments', () {
    test('resolves paymentId from first booking_payments row for online', () {
      final m = _base(
        paymentMethod: 'online',
        bookingPayments: [
          {'id': 'pay-uuid-001', 'status': 'success'},
        ],
      );
      expect(BookingForRefundModel.fromMap(m).paymentId, 'pay-uuid-001');
    });

    test('resolves paymentId for razorpay (legacy) bookings', () {
      final m = _base(
        paymentMethod: 'razorpay',
        bookingPayments: [
          {'id': 'pay-uuid-003', 'status': 'success'},
        ],
      );
      expect(BookingForRefundModel.fromMap(m).paymentId, 'pay-uuid-003');
    });

    test('paymentId is null for cod even if booking_payments present', () {
      final m = _base(
        paymentMethod: 'cod',
        bookingPayments: [
          {'id': 'pay-uuid-002', 'status': 'success'},
        ],
      );
      expect(BookingForRefundModel.fromMap(m).paymentId, isNull);
    });

    test('paymentId is null for online with no booking_payments', () {
      final m = _base(paymentMethod: 'online', bookingPayments: const []);
      expect(BookingForRefundModel.fromMap(m).paymentId, isNull);
    });
  });

  group('BookingForRefundModel display helpers', () {
    test('formattedDate formats service_date correctly', () {
      final m = _base(serviceDate: '2026-09-10');
      expect(BookingForRefundModel.fromMap(m).formattedDate, '10 Sep 2026');
    });

    test('formattedAmount formats ₹500 correctly', () {
      final m = _base(totalAmount: 500.0);
      expect(BookingForRefundModel.fromMap(m).formattedAmount, '₹500');
    });

    test('formattedAmount formats ₹0 correctly — zero-cost rework not excluded by model', () {
      final m = _base(totalAmount: 0.0);
      expect(BookingForRefundModel.fromMap(m).formattedAmount, '₹0');
    });
  });

  group('Rework booking identification — service layer concern', () {
    // The model itself has no isRework field.  Rework bookings look identical
    // to normal bookings from the model's perspective; they are excluded by
    // RefundQueriesService.fetchBookingsForRefund which queries service_warranties
    // and filters out bookingIds that appear as rework_booking_id there.
    //
    // These tests document that a ₹0 booking is NOT excluded by the model alone,
    // which is the specified behaviour (requirement: do not exclude on price).

    test('zero-amount booking is not filtered by model — filtering is service-level', () {
      final reworkLookalike = _base(
        id: 'bk-rework-001',
        totalAmount: 0.0,
        bookingItems: [_catalogItem('AC Warranty Rework')],
      );
      final b = BookingForRefundModel.fromMap(reworkLookalike);
      // Model can still be constructed; the service layer is responsible for
      // filtering before construction.
      expect(b.id, 'bk-rework-001');
      expect(b.totalAmount, 0.0);
    });

    test('non-zero cancelled booking remains eligible at model level', () {
      final m = _base(
        status: 'cancelled',
        totalAmount: 300.0,
        bookingItems: [_catalogItem('Deep Clean')],
      );
      final b = BookingForRefundModel.fromMap(m);
      expect(b.status, 'cancelled');
      expect(b.totalAmount, 300.0);
    });
  });

  // ── displayBookingNumber consistency ─────────────────────────────────────────
  // Verifies that the reference shown to the customer is always in the canonical
  // BK-{FIRST8CHARS} format and never the raw UUID.

  group('displayBookingNumber — canonical reference format', () {
    const uuid = 'c86b1c92-aaaa-bbbb-cccc-000000000000';
    const expectedRef = 'BK-C86B1C92';

    test('null booking_number falls back to BK-{first8ofId}', () {
      final m = _base(id: uuid)..['booking_number'] = null;
      final b = BookingForRefundModel.fromMap(m);
      expect(b.displayBookingNumber, expectedRef);
    });

    test('stored booking_number takes precedence over UUID fallback', () {
      final m = _base(id: uuid, bookingNumber: 'BK-CUSTOM01');
      final b = BookingForRefundModel.fromMap(m);
      expect(b.displayBookingNumber, 'BK-CUSTOM01');
    });

    test('after backfill — stored value matches previously-generated fallback', () {
      // Migration 20260923000007 writes 'BK-' + UPPER(LEFT(id,8)) into booking_number.
      // After backfill, displayBookingNumber must return the same value as before
      // the migration (when it was computed client-side from the UUID).
      final backfilledRef = 'BK-${uuid.substring(0, 8).toUpperCase()}';
      expect(backfilledRef, expectedRef);

      final m = _base(id: uuid, bookingNumber: backfilledRef);
      final b = BookingForRefundModel.fromMap(m);
      expect(b.displayBookingNumber, expectedRef);
    });

    test('reference never equals the raw UUID', () {
      final m = _base(id: uuid)..['booking_number'] = null;
      final b = BookingForRefundModel.fromMap(m);
      expect(b.displayBookingNumber, isNot(equals(uuid)));
      expect(b.displayBookingNumber, startsWith('BK-'));
    });

    test('last 5 chars of UUID portion are found in raw UUID — admin search works', () {
      // Admin searches by the last 5 chars the customer reads off their screen.
      // The BK- reference suffix is the first 8 chars of the UUID in upper case.
      // Last 5 of those 8 chars must appear in the raw UUID string (case-insensitive)
      // so the admin panel's id::text ILIKE '%query%' filter finds the booking.
      final m = _base(id: uuid)..['booking_number'] = null;
      final b = BookingForRefundModel.fromMap(m);
      final refSuffix = b.displayBookingNumber.substring(3); // 'C86B1C92'
      final last5 = refSuffix.substring(refSuffix.length - 5); // 'B1C92'
      expect(uuid.toUpperCase().contains(last5), isTrue);
    });
  });
}
