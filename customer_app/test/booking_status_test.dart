import 'package:flutter_test/flutter_test.dart';
import 'package:customer_app/models/my_booking_model.dart';
import 'package:customer_app/models/address_model.dart';

const _base = AddressModel(
  id: '',
  label: 'Home',
  line1: '1 Test Street',
  city: 'Hyderabad',
  state: 'Telangana',
  pincode: '500001',
);

final _created = DateTime(2024, 6, 1, 10, 0);

MyBookingModel _booking(String status, {String assignmentType = 'External Vendor'}) =>
    MyBookingModel(
      id: 'bk-001',
      serviceId: 's1',
      serviceName: 'AC Repair',
      address: _base,
      scheduledDate: DateTime(2024, 6, 5),
      timeSlot: '10:00 AM',
      baseAmount: 500.0,
      taxAmount: 90.0,
      totalAmount: 590.0,
      status: status,
      assignmentType: assignmentType,
      createdAt: _created,
    );

void main() {
  group('BookingStatus constants', () {
    test('all status strings are defined', () {
      expect(BookingStatus.pending, 'pending');
      expect(BookingStatus.assigned, 'assigned');
      expect(BookingStatus.accepted, 'accepted');
      expect(BookingStatus.enRoute, 'en_route');
      expect(BookingStatus.inProgress, 'in_progress');
      expect(BookingStatus.awaitingVerification, 'awaiting_verification');
      expect(BookingStatus.completed, 'completed');
      expect(BookingStatus.cancelled, 'cancelled');
    });

    test('busyStatuses contains vendor-active statuses', () {
      expect(BookingStatus.busyStatuses, contains('assigned'));
      expect(BookingStatus.busyStatuses, contains('accepted'));
      expect(BookingStatus.busyStatuses, contains('en_route'));
      expect(BookingStatus.busyStatuses, contains('in_progress'));
      expect(BookingStatus.busyStatuses, contains('awaiting_verification'));
      expect(BookingStatus.busyStatuses, isNot(contains('completed')));
      expect(BookingStatus.busyStatuses, isNot(contains('cancelled')));
      expect(BookingStatus.busyStatuses, isNot(contains('pending')));
    });
  });

  group('BookingStatus.labelFor', () {
    test('pending returns Booking Placed', () {
      expect(BookingStatus.labelFor('pending'), 'Booking Placed');
    });

    test('assigned returns Vendor Assigned', () {
      expect(BookingStatus.labelFor('assigned'), 'Vendor Assigned');
    });

    test('completed returns Service Completed', () {
      expect(BookingStatus.labelFor('completed'), 'Service Completed');
    });

    test('cancelled returns Cancelled', () {
      expect(BookingStatus.labelFor('cancelled'), 'Cancelled');
    });

    test('unknown status returns the raw status string', () {
      expect(BookingStatus.labelFor('some_future_status'), 'some_future_status');
    });

    test('DODO Team assignment uses dodo stage labels', () {
      expect(
        BookingStatus.labelFor('assigned_to_dodo_team', assignmentType: 'DODO Team'),
        'Assigned to DODO Team',
      );
    });
  });

  group('BookingStatus.buildTimeline — External Vendor', () {
    test('pending: only first step reached', () {
      final tl = BookingStatus.buildTimeline('pending', _created);
      expect(tl.first.isReached, true);
      expect(tl.first.status, 'pending');
      // All subsequent steps not reached
      for (final e in tl.skip(1)) {
        expect(e.isReached, false, reason: 'step ${e.status} should not be reached');
      }
    });

    test('assigned: first two steps reached', () {
      final tl = BookingStatus.buildTimeline('assigned', _created);
      expect(tl[0].isReached, true); // pending
      expect(tl[1].isReached, true); // assigned
      expect(tl[2].isReached, false); // accepted
    });

    test('completed: all steps reached', () {
      final tl = BookingStatus.buildTimeline('completed', _created);
      for (final e in tl) {
        expect(e.isReached, true, reason: 'step ${e.status} should be reached');
      }
    });

    test('cancelled: only the Booking Placed step is reached', () {
      final tl = BookingStatus.buildTimeline('cancelled', _created);
      expect(tl.first.isReached, true);
      for (final e in tl.skip(1)) {
        expect(e.isReached, false, reason: 'step ${e.status} should not be reached after cancel');
      }
    });

    test('started is treated identically to in_progress', () {
      final tlStarted = BookingStatus.buildTimeline('started', _created);
      final tlInProgress = BookingStatus.buildTimeline('in_progress', _created);
      for (var i = 0; i < tlStarted.length; i++) {
        expect(tlStarted[i].isReached, tlInProgress[i].isReached);
      }
    });

    test('first step carries the base timestamp, others are null', () {
      final tl = BookingStatus.buildTimeline('assigned', _created);
      expect(tl.first.timestamp, _created);
      for (final e in tl.skip(1)) {
        expect(e.timestamp, isNull, reason: 'only step 0 should have a timestamp');
      }
    });

    test('timeline has 7 stages for External Vendor', () {
      expect(BookingStatus.buildTimeline('pending', _created).length, 7);
    });
  });

  group('BookingStatus.buildTimeline — DODO Team', () {
    test('timeline has 5 stages for DODO Team', () {
      expect(
        BookingStatus.buildTimeline('pending', _created, assignmentType: 'DODO Team').length,
        5,
      );
    });

    test('assigned_to_dodo_team: first two steps reached', () {
      final tl = BookingStatus.buildTimeline(
        'assigned_to_dodo_team',
        _created,
        assignmentType: 'DODO Team',
      );
      expect(tl[0].isReached, true);
      expect(tl[1].isReached, true);
      expect(tl[2].isReached, false);
    });
  });

  group('MyBookingModel computed status properties', () {
    test('pending is upcoming and can cancel', () {
      final b = _booking('pending');
      expect(b.isUpcoming, true);
      expect(b.canCancel, true);
      expect(b.isOngoing, false);
      expect(b.isCompleted, false);
      expect(b.isCancelled, false);
    });

    test('assigned is upcoming and can cancel', () {
      final b = _booking('assigned');
      expect(b.isUpcoming, true);
      expect(b.canCancel, true);
    });

    test('accepted is upcoming and can cancel', () {
      final b = _booking('accepted');
      expect(b.isUpcoming, true);
      expect(b.canCancel, true);
    });

    test('en_route is ongoing and cannot cancel', () {
      final b = _booking('en_route');
      expect(b.isOngoing, true);
      expect(b.canCancel, false);
      expect(b.isUpcoming, false);
    });

    test('in_progress is ongoing and cannot cancel', () {
      final b = _booking('in_progress');
      expect(b.isOngoing, true);
      expect(b.canCancel, false);
    });

    test('awaiting_verification is ongoing and cannot cancel', () {
      final b = _booking('awaiting_verification');
      expect(b.isOngoing, true);
      expect(b.canCancel, false);
    });

    test('completed: isCompleted, canRebook, canReview — cannot cancel', () {
      final b = _booking('completed');
      expect(b.isCompleted, true);
      expect(b.canRebook, true);
      expect(b.canReview, true);
      expect(b.canCancel, false);
    });

    test('cancelled: isCancelled, canRebook — cannot cancel again', () {
      final b = _booking('cancelled');
      expect(b.isCancelled, true);
      expect(b.canRebook, true);
      expect(b.canCancel, false);
    });

    test('DODO team booking: isDodoTeam returns true', () {
      final b = _booking('pending', assignmentType: 'DODO Team');
      expect(b.isDodoTeam, true);
    });

    test('External Vendor booking: isDodoTeam returns false', () {
      expect(_booking('pending').isDodoTeam, false);
    });
  });

  group('MyBookingModel.paymentMethodLabel', () {
    test('cash payment → COD label', () {
      final b = MyBookingModel(
        id: 'bk-pm-1',
        serviceId: 's1',
        serviceName: 'AC',
        address: _base,
        scheduledDate: _created,
        timeSlot: '10:00 AM',
        baseAmount: 500,
        taxAmount: 0,
        totalAmount: 500,
        status: 'completed',
        paymentMethod: 'cash',
        createdAt: _created,
      );
      expect(b.isCod, isTrue);
      expect(b.paymentMethodLabel, 'COD');
    });

    test('cod payment → COD label', () {
      final b = MyBookingModel(
        id: 'bk-pm-2',
        serviceId: 's1',
        serviceName: 'AC',
        address: _base,
        scheduledDate: _created,
        timeSlot: '10:00 AM',
        baseAmount: 500,
        taxAmount: 0,
        totalAmount: 500,
        status: 'completed',
        paymentMethod: 'cod',
        createdAt: _created,
      );
      expect(b.isCod, isTrue);
      expect(b.paymentMethodLabel, 'COD');
    });

    test('online payment → Online label', () {
      final b = MyBookingModel(
        id: 'bk-pm-3',
        serviceId: 's1',
        serviceName: 'AC',
        address: _base,
        scheduledDate: _created,
        timeSlot: '10:00 AM',
        baseAmount: 500,
        taxAmount: 0,
        totalAmount: 500,
        status: 'completed',
        paymentMethod: 'online',
        createdAt: _created,
      );
      expect(b.isCod, isFalse);
      expect(b.paymentMethodLabel, 'Online');
    });

    test('razorpay (legacy DB value) → Online label, not COD', () {
      final b = MyBookingModel(
        id: 'bk-pm-5',
        serviceId: 's1',
        serviceName: 'AC',
        address: _base,
        scheduledDate: _created,
        timeSlot: '10:00 AM',
        baseAmount: 500,
        taxAmount: 0,
        totalAmount: 500,
        status: 'completed',
        paymentMethod: 'razorpay',
        createdAt: _created,
      );
      expect(b.isCod, isFalse);
      expect(b.paymentMethodLabel, 'Online');
    });

    test('missing payment_method defaults to cash → COD label', () {
      // fromJson default: payment_method null → 'cash'
      final b = MyBookingModel(
        id: 'bk-pm-4',
        serviceId: 's1',
        serviceName: 'AC',
        address: _base,
        scheduledDate: _created,
        timeSlot: '10:00 AM',
        baseAmount: 500,
        taxAmount: 0,
        totalAmount: 500,
        status: 'completed',
        createdAt: _created,
        // paymentMethod omitted — uses default 'cash'
      );
      expect(b.paymentMethodLabel, 'COD');
    });

    test('fromJson parses payment_method field', () {
      final json = {
        'id': 'bk-fj-1',
        'customer_id': 'cust-1',
        'service_date': '2026-09-10',
        'status': 'completed',
        'payment_method': 'online',
        'subtotal': 500.0,
        'discount_amount': 0.0,
        'total_amount': 500.0,
        'address': '123 Main St, Hyderabad, Telangana, 500001',
        'notes': 'AC Service · 10:00 AM',
        'created_at': '2026-09-01T10:00:00.000Z',
        'assignment_type': 'External Vendor',
        'booking_items': <dynamic>[],
        'booking_addons': <dynamic>[],
      };
      final b = MyBookingModel.fromJson(json);
      expect(b.paymentMethod, 'online');
      expect(b.paymentMethodLabel, 'Online');
    });

    test('fromJson defaults to cash when payment_method absent', () {
      final json = {
        'id': 'bk-fj-2',
        'customer_id': 'cust-1',
        'service_date': '2026-09-10',
        'status': 'completed',
        // no payment_method key
        'subtotal': 400.0,
        'discount_amount': 0.0,
        'total_amount': 400.0,
        'address': '123 Main St, Hyderabad, Telangana, 500001',
        'notes': 'AC Service · 10:00 AM',
        'created_at': '2026-09-01T10:00:00.000Z',
        'assignment_type': 'External Vendor',
        'booking_items': <dynamic>[],
        'booking_addons': <dynamic>[],
      };
      final b = MyBookingModel.fromJson(json);
      expect(b.paymentMethod, 'cash');
      expect(b.paymentMethodLabel, 'COD');
    });
  });

  group('MyBookingModel.displayBookingNumber', () {
    test('uses bookingNumber when present', () {
      final b = MyBookingModel(
        id: 'uuid-1234-5678',
        bookingNumber: 'BK-2024-001',
        serviceId: 's1',
        serviceName: 'AC',
        address: _base,
        scheduledDate: _created,
        timeSlot: '10:00 AM',
        baseAmount: 100,
        taxAmount: 0,
        totalAmount: 100,
        status: 'pending',
        createdAt: _created,
      );
      expect(b.displayBookingNumber, 'BK-2024-001');
    });

    test('falls back to id prefix when bookingNumber is null', () {
      final b = _booking('pending');
      // id = 'bk-001' (< 8 chars), so returns 'bk-001' directly
      expect(b.displayBookingNumber, isNotEmpty);
    });
  });
}
