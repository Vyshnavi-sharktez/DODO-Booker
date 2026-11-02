import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../widgets/upi_dodo_config_card.dart';

class UpiConfigPage extends StatelessWidget {
  const UpiConfigPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'UPI QR Config',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              'Configure your UPI ID and QR code shown to customers during payment.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey.shade600,
                  ),
            ),
            const SizedBox(height: 24),
            const UpiDodoConfigCard(),
          ],
        ),
      ),
    );
  }
}
