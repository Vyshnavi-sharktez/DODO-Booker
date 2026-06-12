import 'package:flutter/material.dart';
import '../../domain/models/vendor_profile.dart';

class ProfileHeader extends StatelessWidget {
  const ProfileHeader({super.key, required this.profile});

  final VendorProfile profile;

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
