import 'package:flutter/material.dart';
import '../../../../shared/widgets/placeholder_page.dart';

class ServicesPage extends StatelessWidget {
  const ServicesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderModulePage(
      title: 'Services',
      description: 'Manage bookable services, packages and add-ons',
      icon: Icons.home_repair_service_rounded,
    );
  }
}
