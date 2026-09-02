import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:customer_app/features/booking/screens/booking_success_screen.dart';
import 'package:customer_app/models/booking_model.dart';

void main() {
  testWidgets('BookingSuccessScreen renders without overflow for long booking ID', (WidgetTester tester) async {
    // Set small screen size to simulate small mobile device
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;

    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final testBooking = BookingModel(
      id: 'BOOKING-2026-0829-99482818-VERY-LONG-ID-123456789',
      serviceId: 'srv_1',
      serviceName: 'Full House Deep Cleaning & Sanitization Service',
      addressId: 'addr_1',
      addressLabel: 'Home - 123 Main Street',
      scheduledDate: DateTime(2026, 8, 29),
      timeSlot: '10:00 AM - 11:00 AM',
      baseAmount: 1499.0,
      taxAmount: 269.82,
      totalAmount: 1768.82,
      status: 'confirmed',
      createdAt: DateTime(2026, 8, 29),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: BookingSuccessScreen(
          booking: testBooking,
          onViewBookings: () {},
          onBackToHome: () {},
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Booking Confirmed!'), findsOneWidget);
    expect(find.text('BOOKING-2026-0829-99482818-VERY-LONG-ID-123456789'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
