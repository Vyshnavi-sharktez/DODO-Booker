import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/widgets/page_sheet.dart';
import '../../../models/my_booking_model.dart';
import '../screens/booking_details_screen.dart';

/// Opens Booking Details as a floating [PageSheet] dialog on desktop/web
/// (≥768 px), or navigates to the full-screen route on mobile.
///
/// Use this everywhere instead of calling
/// [context.push('/booking-detail/...')] directly so that the desktop
/// experience stays within the modal design system.
void openBookingDetail(BuildContext context, MyBookingModel booking) {
  if (MediaQuery.of(context).size.width >= 768) {
    PageSheet.show(
      context,
      title: 'Booking Details',
      child: BookingDetailsScreen(booking: booking, inModal: true),
    );
  } else {
    context.push('/booking-detail/${booking.id}', extra: booking);
  }
}
