import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'app_header.dart';
import '../../features/home/screens/home_screen.dart';
import '../../routes/app_router.dart';

class AppNavigation extends ConsumerStatefulWidget {
  const AppNavigation({super.key});

  @override
  ConsumerState<AppNavigation> createState() => _AppNavigationState();
}

class _AppNavigationState extends ConsumerState<AppNavigation> {
  bool _scrolled = false;

  bool _onScroll(ScrollNotification notification) {
    final scrolled = notification.metrics.pixels > 8;
    if (scrolled != _scrolled) setState(() => _scrolled = scrolled);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppHeader(
        onLogoTap: () {},
        onProfileTap: () => context.push(AppRoutes.profile),
        isScrolled: _scrolled,
      ),
      body: NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: MediaQuery.removePadding(
          context: context,
          removeTop: true,
          child: const HomeScreen(),
        ),
      ),
    );
  }
}
