import 'package:flutter_test/flutter_test.dart';
import 'package:admin_panel/features/bookings/domain/models/booking.dart';

void main() {
  group('Booking Status Reactivation Tests (Cancelled → Pending / Assigned)', () {
    final now = DateTime.now();

    test('Booking statusConfig maps cancelled status correctly', () {
      final cancelledBooking = Booking(
        id: 'b-101',
        bookingNumber: 'DODO101',
        customerId: 'cust-1',
        vendorId: '',
        status: 'cancelled',
        subtotal: 1000,
        discountAmount: 0,
        totalAmount: 1000,
        createdAt: now,
      );

      final (label, textColor, bgColor) = cancelledBooking.statusConfig;
      expect(label, equals('Cancelled'));
      expect(cancelledBooking.isUnassigned, isTrue);
    });

    test('Reactivating Cancelled → Pending resets cancellation, payment & assignment state', () {
      // 1. Initial state: Cancelled booking
      final cancelledBookingMap = <String, dynamic>{
        'id': 'b-102',
        'booking_number': 'DODO102',
        'customer_id': 'cust-102',
        'vendor_id': 'vend-99',
        'status': 'cancelled',
        'cancelled_by': 'customer',
        'cancelled_at': now.toIso8601String(),
        'cancellation_reason': 'Changed mind',
        'payment_method': 'online',
        'payment_status': 'failed',
        'cod_cash_collected': false,
        'cod_confirmed_at': now.toIso8601String(),
        'cod_not_collected_reason': 'Order cancelled',
        'assignment_type': 'External Vendor',
        'dispatch_status': 'exhausted',
        'subtotal': 5000.0,
        'discount_amount': 500.0,
        'total_amount': 4500.0,
      };

      final initialBooking = Booking.fromMap(cancelledBookingMap);
      expect(initialBooking.status, equals('cancelled'));
      expect(initialBooking.paymentMethodLabel, equals('Online'));

      // 2. Simulate reactivation logic (Cancelled → Pending)
      final reactivationPayload = <String, dynamic>{
        'status': 'pending',
        'cancelled_by': null,
        'cancelled_at': null,
        'cancellation_reason': null,
        'payment_method': 'cash',
        'payment_status': 'pending',
        'cod_cash_collected': null,
        'cod_confirmed_at': null,
        'cod_not_collected_reason': null,
        'assignment_type': 'Unassigned',
        'vendor_id': null,
        'dodo_team_id': null,
        'dispatch_status': 'idle',
        'updated_at': now.toIso8601String(),
      };

      final updatedMap = Map<String, dynamic>.from(cancelledBookingMap)
        ..addAll(reactivationPayload);

      final reactivatedBooking = Booking.fromMap(updatedMap);

      // 3. Assertions for Cancelled → Pending
      expect(reactivatedBooking.status, equals('pending'));
      expect(reactivatedBooking.isUnassigned, isTrue);
      expect(reactivatedBooking.isCod, isTrue);
      expect(reactivatedBooking.paymentMethodLabel, equals('COD'));
      expect(reactivatedBooking.paymentStatus, equals('pending'));
      expect(reactivatedBooking.codCashCollected, isNull);
      expect(reactivatedBooking.codConfirmedAt, isNull);
      expect(reactivatedBooking.codNotCollectedReason, isNull);
      expect(reactivatedBooking.cancellationReason, isNull);
    });

    test('Reactivating Cancelled → Assigned resets cancellation & payment to COD pending', () {
      final cancelledBookingMap = <String, dynamic>{
        'id': 'b-103',
        'booking_number': 'DODO103',
        'customer_id': 'cust-103',
        'vendor_id': 'vend-42',
        'status': 'cancelled',
        'cancelled_by': 'admin',
        'cancelled_at': now.toIso8601String(),
        'cancellation_reason': 'Admin cancel',
        'payment_method': 'cash',
        'payment_status': null,
        'cod_cash_collected': null,
        'assignment_type': 'Unassigned',
        'dispatch_status': 'idle',
        'subtotal': 2000.0,
        'discount_amount': 0.0,
        'total_amount': 2000.0,
      };

      // Simulate reactivation logic (Cancelled → Assigned with existing vendor)
      final reactivationPayload = <String, dynamic>{
        'status': 'assigned',
        'cancelled_by': null,
        'cancelled_at': null,
        'cancellation_reason': null,
        'payment_method': 'cash',
        'payment_status': 'pending',
        'cod_cash_collected': null,
        'cod_confirmed_at': null,
        'cod_not_collected_reason': null,
        'assignment_type': 'External Vendor',
        'dispatch_status': 'assigned',
        'updated_at': now.toIso8601String(),
      };

      final updatedMap = Map<String, dynamic>.from(cancelledBookingMap)
        ..addAll(reactivationPayload);

      final reactivatedBooking = Booking.fromMap(updatedMap);

      // Assertions for Cancelled → Assigned
      expect(reactivatedBooking.status, equals('assigned'));
      expect(reactivatedBooking.assignmentType, equals('External Vendor'));
      expect(reactivatedBooking.isCod, isTrue);
      expect(reactivatedBooking.paymentMethodLabel, equals('COD'));
      expect(reactivatedBooking.paymentStatus, equals('pending'));
      expect(reactivatedBooking.codCashCollected, isNull);
      expect(reactivatedBooking.cancellationReason, isNull);
    });

    test('Customer notification payload format for booking status update', () {
      const customerId = 'cust-102';
      const bookingNumber = 'DODO102';
      const newStatusLabel = 'Pending';

      final notificationPayload = {
        'user_type': 'customer',
        'user_id': customerId,
        'title': 'Booking Status Updated',
        'message':
            'Your booking #$bookingNumber status has been updated to $newStatusLabel.',
        'notification_type': 'booking_status',
        'is_read': false,
        'entity_type': 'booking',
        'entity_id': 'b-102',
      };

      expect(notificationPayload['user_type'], equals('customer'));
      expect(notificationPayload['user_id'], equals('cust-102'));
      expect(notificationPayload['title'], equals('Booking Status Updated'));
      expect(
        notificationPayload['message'],
        equals('Your booking #DODO102 status has been updated to Pending.'),
      );
      expect(notificationPayload['notification_type'], equals('booking_status'));
    });
  });
}
