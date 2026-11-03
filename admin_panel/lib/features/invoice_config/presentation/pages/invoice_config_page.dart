import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../widgets/invoice_config_card.dart';

class InvoiceConfigPage extends StatelessWidget {
  const InvoiceConfigPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Invoice Configuration',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              'Company branding and settings applied to all new invoices. '
              'Existing invoices are preserved in storage and are not affected by changes here.',
              style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 24),
            const InvoiceConfigCard(),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
