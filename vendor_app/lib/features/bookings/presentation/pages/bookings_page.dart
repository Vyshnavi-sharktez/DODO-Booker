import 'package:flutter/material.dart';
import '../../../../core/widgets/vendor_scaffold.dart';

class BookingsPage extends StatelessWidget {
  const BookingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const VendorScaffold(
      title: 'Bookings',
      child: Center(child: Text('Bookings')),
    );
  }
}
