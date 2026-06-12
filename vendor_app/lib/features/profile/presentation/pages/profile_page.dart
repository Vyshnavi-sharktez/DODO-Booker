import 'package:flutter/material.dart';
import '../../../../core/widgets/vendor_scaffold.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const VendorScaffold(
      title: 'Profile',
      child: Center(child: Text('Profile')),
    );
  }
}
