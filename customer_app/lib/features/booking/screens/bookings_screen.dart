import 'package:flutter/material.dart';
import '../../bookings/screens/my_bookings_screen.dart';

// Tab-shell entry point — delegates to the full My Bookings implementation.
class BookingsScreen extends StatelessWidget {
  const BookingsScreen({super.key});

  @override
  Widget build(BuildContext context) => const MyBookingsScreen();
}
