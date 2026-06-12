import 'package:flutter/material.dart';
import '../../../../core/widgets/vendor_scaffold.dart';

class ServicesPage extends StatelessWidget {
  const ServicesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const VendorScaffold(
      title: 'My Services',
      child: Center(child: Text('My Services')),
    );
  }
}
