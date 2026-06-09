import 'package:flutter/material.dart';
import '../../../../shared/widgets/placeholder_page.dart';

class CustomersPage extends StatelessWidget {
  const CustomersPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderModulePage(
      title: 'Customers',
      description: 'View and manage customer profiles and history',
      icon: Icons.people_rounded,
    );
  }
}
