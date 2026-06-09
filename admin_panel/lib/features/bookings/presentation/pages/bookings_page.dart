import 'package:flutter/material.dart';
import '../../../../shared/widgets/placeholder_page.dart';

class BookingsPage extends StatelessWidget {
  const BookingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderModulePage(
      title: 'Bookings',
      description: 'Manage the full booking lifecycle',
      icon: Icons.book_online_rounded,
    );
  }
}
