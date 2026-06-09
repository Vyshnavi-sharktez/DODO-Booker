import 'package:flutter/material.dart';
import '../../../../shared/widgets/placeholder_page.dart';

class CouponsPage extends StatelessWidget {
  const CouponsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderModulePage(
      title: 'Coupons & Promotions',
      description: 'Create and manage coupons and promotional campaigns',
      icon: Icons.local_offer_rounded,
    );
  }
}
