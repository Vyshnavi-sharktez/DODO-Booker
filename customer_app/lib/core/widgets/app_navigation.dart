import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'app_header.dart';
import '../../features/home/screens/home_screen.dart';
import '../../routes/app_router.dart';

class AppNavigation extends ConsumerWidget {
  const AppNavigation({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppHeader(
        onLogoTap: () {},
        onProfileTap: () => context.push(AppRoutes.profile),
      ),
      body: MediaQuery.removePadding(
        context: context,
        removeTop: true,
        child: const HomeScreen(),
      ),
    );
  }
}
