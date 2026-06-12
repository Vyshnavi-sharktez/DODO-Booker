import 'package:flutter/material.dart';
import '../../../../core/widgets/vendor_scaffold.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const VendorScaffold(
      title: 'Dashboard',
      child: Center(child: Text('Dashboard')),
    );
  }
}
