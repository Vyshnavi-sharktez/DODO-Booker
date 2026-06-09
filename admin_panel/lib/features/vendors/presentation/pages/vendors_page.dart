import 'package:flutter/material.dart';
import '../../../../shared/widgets/placeholder_page.dart';

class VendorsPage extends StatelessWidget {
  const VendorsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderModulePage(
      title: 'Vendors',
      description: 'Manage vendor onboarding, verification and lifecycle',
      icon: Icons.store_rounded,
    );
  }
}
