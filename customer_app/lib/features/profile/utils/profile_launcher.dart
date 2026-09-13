import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/widgets/page_sheet.dart';
import '../../../routes/app_router.dart';
import '../screens/profile_screen.dart';

/// Opens My Account as a floating [PageSheet] on desktop/web (≥ 768 px),
/// or navigates to the full-screen route on mobile.
void openProfile(BuildContext context) {
  if (MediaQuery.of(context).size.width >= 768) {
    PageSheet.show(
      context,
      title: 'My Account',
      child: const ProfileScreen(inModal: true),
    );
  } else {
    context.push(AppRoutes.profile);
  }
}
