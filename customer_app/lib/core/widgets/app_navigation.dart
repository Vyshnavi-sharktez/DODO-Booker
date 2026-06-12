import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app_header.dart';
import 'app_modal_dialog.dart';
import '../../features/auth/utils/auth_modal_gate.dart';
import '../../features/home/screens/home_screen.dart';
import '../../features/category/screens/category_screen.dart';
import '../../features/profile/screens/profile_screen.dart';
import '../../features/bookings/modals/my_bookings_modal.dart';
import '../../features/wishlist/screens/wishlist_screen.dart';

class AppNavigation extends ConsumerStatefulWidget {
  const AppNavigation({super.key});

  @override
  ConsumerState<AppNavigation> createState() => _AppNavigationState();
}

class _AppNavigationState extends ConsumerState<AppNavigation> {
  // Nav-bar index (0=Home, 1=Categories, 2=Bookings[modal], 3=Wishlist, 4=Profile)
  int _navIndex = 0;

  // IndexedStack holds 4 page tabs; Bookings (index 2) is a modal — not a page.
  // Nav→stack mapping: 0→0, 1→1, (2=modal), 3→2, 4→3
  static const List<Widget> _screens = [
    HomeScreen(),
    CategoryScreen(),
    WishlistScreen(),
    ProfileScreen(),
  ];

  int get _stackIndex {
    if (_navIndex >= 3) return _navIndex - 1;
    return _navIndex; // 0, 1  (2 is a modal, never used as stack index)
  }

  static const List<NavigationDestination> _destinations = [
    NavigationDestination(
      icon: Icon(Icons.home_outlined),
      selectedIcon: Icon(Icons.home_rounded),
      label: 'Home',
    ),
    NavigationDestination(
      icon: Icon(Icons.grid_view_outlined),
      selectedIcon: Icon(Icons.grid_view_rounded),
      label: 'Categories',
    ),
    NavigationDestination(
      icon: Icon(Icons.receipt_long_outlined),
      selectedIcon: Icon(Icons.receipt_long_rounded),
      label: 'Bookings',
    ),
    NavigationDestination(
      icon: Icon(Icons.favorite_border_rounded),
      selectedIcon: Icon(Icons.favorite_rounded),
      label: 'Wishlist',
    ),
    NavigationDestination(
      icon: Icon(Icons.person_outline_rounded),
      selectedIcon: Icon(Icons.person_rounded),
      label: 'Profile',
    ),
  ];

  Future<void> _onDestinationSelected(int index) async {
    if (index == 2) {
      // Bookings → require auth, then open modal (no page change)
      final authed = await requireAuth(context, ref);
      if (!mounted || !authed) return;
      if (!mounted) return;
      await AppModalDialog.show(context: context, child: const MyBookingsModal());
      return;
    }
    if (index == 3) {
      // Wishlist → require auth, then switch to wishlist page
      final authed = await requireAuth(context, ref);
      if (!mounted || !authed) return;
    }
    setState(() => _navIndex = index);
  }

  void _goHome() => setState(() => _navIndex = 0);
  void _goProfile() => setState(() => _navIndex = 4);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppHeader(
        onLogoTap: _goHome,
        onProfileTap: _goProfile,
      ),
      body: MediaQuery.removePadding(
        context: context,
        removeTop: true,
        child: IndexedStack(
          index: _stackIndex,
          children: _screens,
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _navIndex,
        onDestinationSelected: _onDestinationSelected,
        destinations: _destinations,
      ),
    );
  }
}
