import 'package:flutter/material.dart';
import '../../../../shared/widgets/placeholder_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderModulePage(
      title: 'Settings',
      description: 'Configure platform settings, commissions and tax rules',
      icon: Icons.settings_rounded,
    );
  }
}
