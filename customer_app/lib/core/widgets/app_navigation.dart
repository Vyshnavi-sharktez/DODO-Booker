import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../constants/app_colors.dart';
import 'app_header.dart';
import 'app_modal_dialog.dart';
import '../../features/home/screens/home_screen.dart';
import '../../features/home/services/home_providers.dart';
import '../../features/home/widgets/hero_section.dart';
import '../../features/notifications/widgets/notifications_modal.dart';
import '../../features/notifications/services/notification_providers.dart';
import '../../features/cart/providers/cart_provider.dart';
import '../../routes/app_router.dart';
import 'mobile_cart_bar.dart';

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
    final isMobile = MediaQuery.sizeOf(context).width < 768;

    if (isMobile) {
      final servicesUnlocked = ref.watch(mobileServicesUnlockedProvider);

      // ── Pre-unlock: hero-only, serviceability-first ──────────────────────────
      if (!servicesUnlocked) {
        return Scaffold(
          backgroundColor: const Color(0xFF111111),
          body: SafeArea(
            child: HeroSection(
              onBookNow: () => context.push('/search'),
              onExplore: () => context.push('/search'),
            ),
          ),
        );
      }

      // ── Post-unlock: full home with bottom nav ───────────────────────────────
      return Scaffold(
        backgroundColor: const Color(0xFFFBF8F3),
        body: NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: const HomeScreen(showMobileHeader: true),
        ),
        bottomNavigationBar: const _MobileBottomNavWithCartBar(),
      );
    }

    // ── Desktop / tablet ───────────────────────────────────────────────────────
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

// ── Mobile bottom navigation ──────────────────────────────────────────────────

class _MobileBottomNav extends ConsumerWidget {
  const _MobileBottomNav();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unreadCount = ref.watch(unreadCountProvider);

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Color(0xFFECE7DE), width: 0.8),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Row(
            children: [
              _BottomNavItem(
                icon: Icons.home_rounded,
                label: 'Home',
                active: true,
                badge: 0,
                onTap: () => context.go(AppRoutes.home),
              ),
              _BottomNavItem(
                icon: Icons.calendar_today_rounded,
                label: 'Bookings',
                active: false,
                badge: 0,
                onTap: () => context.push(AppRoutes.myBookings),
              ),
              _BottomNavItem(
                icon: Icons.notifications_outlined,
                label: 'Alerts',
                active: false,
                badge: unreadCount,
                onTap: () => AppModalDialog.show(
                  context: context,
                  child: const NotificationsModal(),
                ),
              ),
              _BottomNavItem(
                icon: Icons.person_outline_rounded,
                label: 'Profile',
                active: false,
                badge: 0,
                onTap: () => context.push(AppRoutes.profile),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Mobile bottom nav + floating cart bar (stacked) ──────────────────────────

class _MobileBottomNavWithCartBar extends ConsumerWidget {
  const _MobileBottomNavWithCartBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cartCount = ref.watch(cartItemCountProvider);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (cartCount > 0) const MobileCartBar(),
        const _MobileBottomNav(),
      ],
    );
  }
}

class _BottomNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final int badge;
  final VoidCallback onTap;

  const _BottomNavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.badge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.gold : const Color(0xFF9A948C);
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(icon, color: color, size: 22),
                if (badge > 0)
                  Positioned(
                    top: -4,
                    right: -6,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: const BoxDecoration(
                        color: Color(0xFFE53935),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        badge > 9 ? '9+' : '$badge',
                        style: const TextStyle(
                          fontSize: 8,
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
