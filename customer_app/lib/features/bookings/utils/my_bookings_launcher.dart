import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/widgets/page_sheet.dart';
import '../modals/my_bookings_modal.dart';

/// Opens My Bookings as a floating [PageSheet] dialog on desktop/web (≥768 px),
/// or navigates to the full-screen route on mobile.
///
/// Use this everywhere instead of calling [context.push('/my-bookings')] directly
/// so that the desktop experience is always consistent.
void openMyBookings(BuildContext context) {
  if (MediaQuery.of(context).size.width >= 768) {
    PageSheet.show(
      context,
      title: 'My Bookings',
      child: const MyBookingsModal(),
    );
  } else {
    context.push('/my-bookings');
  }
}
