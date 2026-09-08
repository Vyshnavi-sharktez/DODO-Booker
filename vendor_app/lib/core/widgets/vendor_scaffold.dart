import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../constants/app_colors.dart';
import '../routes/route_names.dart';
import '../../features/auth/presentation/providers/auth_controller.dart';
import '../../features/location/application/location_tracking_service.dart';
import '../../features/notifications/presentation/providers/notifications_provider.dart';
import '../../features/notifications/presentation/widgets/vendor_notifications_panel.dart';
import '../../features/profile/domain/models/vendor_profile.dart';
import '../../features/profile/presentation/pages/edit_profile_page.dart';
import '../../features/profile/presentation/providers/profile_provider.dart';

final vendorProfilePanelProvider = StateProvider<bool>((ref) => false);
const _kProfilePanelWidth = 340.0;

/// Shared scaffold for all authenticated pages.
///
/// Narrow (< 720 px): AppBar + body + BottomNavigationBar — unchanged mobile UX.
/// Wide  (≥ 720 px): Fixed 220 px left sidebar + top header strip + body.
class VendorScaffold extends ConsumerWidget {
  const VendorScaffold({
    super.key,
    required this.title,
    required this.child,
    this.actions,
  });

  final String title;
  final Widget child;
  final List<Widget>? actions;

  // Width at which the sidebar replaces the bottom nav.
  static const double _sidebarBreakpoint = 720;

  static const _tabs = [
    _NavTab(
      path: RoutePaths.dashboard,
      label: 'Dashboard',
      icon: Icons.dashboard_outlined,
      selectedIcon: Icons.dashboard_rounded,
    ),
    _NavTab(
      path: RoutePaths.bookings,
      label: 'Bookings',
      icon: Icons.book_online_outlined,
      selectedIcon: Icons.book_online_rounded,
    ),
    _NavTab(
      path: RoutePaths.services,
      label: 'Services',
      icon: Icons.home_repair_service_outlined,
      selectedIcon: Icons.home_repair_service_rounded,
    ),
    _NavTab(
      path: RoutePaths.profile,
      label: 'Profile',
      icon: Icons.person_outline_rounded,
      selectedIcon: Icons.person_rounded,
    ),
    _NavTab(
      path: RoutePaths.settings,
      label: 'Settings',
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(activeBookingTrackerObserver, (_, _) {});

    // Listen for incoming dispatch notifications and present in-app banner.
    ref.listen<AsyncValue<List<VendorNotification>>>(
      vendorNotificationsProvider,
      (previous, next) {
        final notifications = next.valueOrNull;
        if (notifications == null || notifications.isEmpty) return;

        final handledIds = ref.read(handledDispatchNotifIdsProvider);

        for (final n in notifications) {
          if (n.isRead) continue;
          final isDispatchReq = n.title == 'New Booking Request' ||
              n.notificationType == 'vendor_assigned' ||
              n.notificationType == 'new_dispatch_offer';
          if (!isDispatchReq) continue;
          if (handledIds.contains(n.id)) continue;

          ref.read(handledDispatchNotifIdsProvider.notifier).state = {
            ...ref.read(handledDispatchNotifIdsProvider.notifier).state,
            n.id,
          };

          if (context.mounted) {
            ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
            ScaffoldMessenger.of(context).showMaterialBanner(
              MaterialBanner(
                elevation: 4,
                backgroundColor: AppColors.primary,
                leading: const Icon(Icons.bolt_rounded,
                    color: Colors.white, size: 28),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'New Booking Request',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      n.message.isNotEmpty
                          ? n.message
                          : 'You have a new dispatch offer! Tap to review.',
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => ScaffoldMessenger.of(context)
                        .hideCurrentMaterialBanner(),
                    child: const Text('DISMISS',
                        style: TextStyle(color: Colors.white70)),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20)),
                    ),
                    onPressed: () {
                      ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
                      if (n.entityType == 'booking' && n.entityId != null) {
                        context.pushNamed(
                          RouteNames.bookingDetail,
                          pathParameters: {'id': n.entityId!},
                        );
                      } else {
                        context.pushNamed(RouteNames.notifications);
                      }
                    },
                    child: const Text('VIEW OFFER'),
                  ),
                ],
              ),
            );
          }
          break;
        }
      },
    );

    final location = GoRouterState.of(context).matchedLocation;
    final currentIndex =
        _tabs.indexWhere((t) => t.path == location).clamp(0, _tabs.length - 1);
    final unreadCount = ref.watch(vendorUnreadCountProvider);
    final isPanelOpen = ref.watch(vendorProfilePanelProvider);

    // True only when on one of the five primary tab pages.
    final isTabPage = _tabs.any((t) => t.path == location);
    final isRootTab = location == RoutePaths.dashboard;

    void openPanel() =>
        ref.read(vendorProfilePanelProvider.notifier).state = true;
    void closePanel() =>
        ref.read(vendorProfilePanelProvider.notifier).state = false;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= _sidebarBreakpoint;

        void openProfilePanel() {
          if (isWide) {
            openPanel();
          } else {
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.white,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              builder: (ctx) => SizedBox(
                height: MediaQuery.of(context).size.height * 0.85,
                child: _VendorProfilePanel(
                  onClose: () => Navigator.of(ctx).pop(),
                ),
              ),
            );
          }
        }

        return PopScope(
          canPop: !isTabPage || isRootTab,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) context.go(RoutePaths.dashboard);
          },
          child: isWide
              ? _buildWideLayout(context, location, unreadCount, isPanelOpen,
                  openProfilePanel, closePanel)
              : _buildNarrowLayout(context, location, currentIndex, unreadCount,
                  openProfilePanel),
        );
      },
    );
  }

  // ── Wide layout: sidebar + top header ────────────────────────────────────────

  Widget _buildWideLayout(
    BuildContext context,
    String location,
    int unreadCount,
    bool isPanelOpen,
    VoidCallback openProfilePanel,
    VoidCallback closePanel,
  ) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Row(
        children: [
          _VendorSidebarNav(
            tabs: _tabs,
            location: location,
            isProfilePanelOpen: isPanelOpen,
            onProfileTap: openProfilePanel,
            onNavigate: closePanel,
          ),
          Expanded(
            child: Stack(
              children: [
                Column(
                  children: [
                    _VendorTopHeader(
                      title: title,
                      actions: actions,
                      unreadCount: unreadCount,
                      onNotifTap: () => showDialog(
                        context: context,
                        barrierColor: Colors.black12,
                        builder: (_) => const VendorNotificationsPanelDialog(),
                      ),
                    ),
                    Expanded(child: child),
                  ],
                ),
                // Barrier — tapping outside the panel closes it.
                if (isPanelOpen)
                  Positioned.fill(
                    child: GestureDetector(
                      onTap: closePanel,
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                          color: Colors.black.withValues(alpha: 0.25)),
                    ),
                  ),
                // Profile panel — slides in/out from the right edge.
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOutCubic,
                  top: 0,
                  bottom: 0,
                  right: isPanelOpen ? 0 : -_kProfilePanelWidth,
                  width: _kProfilePanelWidth,
                  child: _VendorProfilePanel(onClose: closePanel),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Narrow layout: AppBar + body + bottom nav ─────────────────────────────────

  Widget _buildNarrowLayout(
    BuildContext context,
    String location,
    int currentIndex,
    int unreadCount,
    VoidCallback openProfilePanel,
  ) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          ...?actions,
          _NotificationBell(
            unreadCount: unreadCount,
            onTap: () => showDialog(
              context: context,
              barrierColor: Colors.black12,
              builder: (_) => const VendorNotificationsPanelDialog(),
            ),
          ),
        ],
      ),
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: (i) {
          if (_tabs[i].path == RoutePaths.profile) {
            openProfilePanel();
          } else if (_tabs[i].path != location) {
            context.go(_tabs[i].path);
          }
        },
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.primaryLight,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: _tabs
            .map(
              (t) => NavigationDestination(
                icon: Icon(t.icon),
                selectedIcon: Icon(t.selectedIcon),
                label: t.label,
              ),
            )
            .toList(),
      ),
    );
  }
}

// ── Sidebar palette — black/white theme ──────────────────────────────────────
const _sbBg       = Color(0xFF111111); // sidebar background
const _sbBorder   = Color(0xFF2A2A2A); // sidebar divider / border
const _sbText     = Color(0xFFCCCCCC); // sidebar nav text
const _sbSubtitle = Color(0xFF888888); // subtitle / muted text in sidebar
const _sbAccent   = Color(0xFFFFFFFF); // active item accent (white)

// ── Sidebar navigation (desktop) ─────────────────────────────────────────────

class _VendorSidebarNav extends StatelessWidget {
  const _VendorSidebarNav({
    required this.tabs,
    required this.location,
    required this.isProfilePanelOpen,
    required this.onProfileTap,
    required this.onNavigate,
  });

  final List<_NavTab> tabs;
  final String location;
  final bool isProfilePanelOpen;
  final VoidCallback onProfileTap;
  // Called when any non-profile tab is tapped, so the panel can be closed.
  final VoidCallback onNavigate;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      color: _sbBg,
      child: Column(
        children: [
          const _SidebarBrand(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                for (final tab in tabs)
                  _SidebarTile(
                    tab: tab,
                    isActive: tab.path == RoutePaths.profile
                        ? isProfilePanelOpen
                        : tab.path == RoutePaths.dashboard
                            ? location == RoutePaths.dashboard
                            : location.startsWith(tab.path),
                    onTap: tab.path == RoutePaths.profile
                        ? onProfileTap
                        : () {
                            onNavigate();
                            context.go(tab.path);
                          },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarBrand extends StatelessWidget {
  const _SidebarBrand();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _sbBorder)),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.all(3),
            child: Image.asset(
              'assets/images/logo.png',
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'DODO VENDOR',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
                Text(
                  'Vendor Portal',
                  style: TextStyle(
                    color: _sbSubtitle,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarTile extends StatefulWidget {
  const _SidebarTile({
    required this.tab,
    required this.isActive,
    required this.onTap,
  });

  final _NavTab tab;
  final bool isActive;
  final VoidCallback onTap;

  @override
  State<_SidebarTile> createState() => _SidebarTileState();
}

class _SidebarTileState extends State<_SidebarTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.isActive;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: active
                ? Colors.white.withValues(alpha: 0.15)
                : _hovered
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: active
                ? Border.all(color: Colors.white.withValues(alpha: 0.30))
                : Border.all(color: Colors.transparent),
          ),
          child: Row(
            children: [
              Icon(
                active ? widget.tab.selectedIcon : widget.tab.icon,
                size: 18,
                color: active ? Colors.white : _sbText,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.tab.label,
                  style: TextStyle(
                    color: active ? Colors.white : _sbText,
                    fontSize: 13.5,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              if (active)
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: _sbAccent,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Top header strip (desktop) ────────────────────────────────────────────────

class _VendorTopHeader extends StatelessWidget {
  const _VendorTopHeader({
    required this.title,
    required this.actions,
    required this.unreadCount,
    required this.onNotifTap,
  });

  final String title;
  final List<Widget>? actions;
  final int unreadCount;
  final VoidCallback onNotifTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          ...?actions,
          const SizedBox(width: 4),
          _NotificationBell(unreadCount: unreadCount, onTap: onNotifTap),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

// ── Notification bell with badge ──────────────────────────────────────────────

class _NotificationBell extends StatelessWidget {
  const _NotificationBell({
    required this.unreadCount,
    required this.onTap,
  });

  final int unreadCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          icon: const Icon(Icons.notifications_outlined),
          tooltip: 'Notifications',
          onPressed: onTap,
        ),
        if (unreadCount > 0)
          Positioned(
            top: 8,
            right: 8,
            child: IgnorePointer(
              child: Container(
                constraints:
                    const BoxConstraints(minWidth: 16, minHeight: 16),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: AppColors.error,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  unreadCount > 99 ? '99+' : '$unreadCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    height: 1.6,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ── Nav tab descriptor ────────────────────────────────────────────────────────

class _NavTab {
  const _NavTab({
    required this.path,
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String path;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

// ── Profile side panel ────────────────────────────────────────────────────────

class _VendorProfilePanel extends ConsumerStatefulWidget {
  const _VendorProfilePanel({required this.onClose});
  final VoidCallback onClose;

  @override
  ConsumerState<_VendorProfilePanel> createState() =>
      _VendorProfilePanelState();
}

class _VendorProfilePanelState extends ConsumerState<_VendorProfilePanel> {
  bool _uploading = false;

  Future<void> _pickAndUpload() async {
    final vendor = ref.read(currentVendorUserProvider);
    if (vendor == null) return;

    final XFile? file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (file == null || !mounted) return;

    final ext = file.name.split('.').last.toLowerCase();
    if (!{'jpg', 'jpeg', 'png', 'webp'}.contains(ext)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('Unsupported format. Use jpg, jpeg, png or webp.')),
        );
      }
      return;
    }

    final contentType = switch (ext) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => 'image/jpeg',
    };

    setState(() => _uploading = true);
    try {
      final bytes = await file.readAsBytes();
      await ref.read(uploadProfilePhotoUseCaseProvider)(
        vendorId: vendor.id,
        bytes: bytes,
        contentType: contentType,
      );
      ref.invalidate(vendorProfileProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile photo updated')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _navigate(Widget page) {
    widget.onClose();
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  void _pushRoute(String path) {
    widget.onClose();
    context.push(path);
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(vendorProfileProvider);

    return Material(
      color: Colors.white,
      elevation: 0,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(left: BorderSide(color: AppColors.border)),
          boxShadow: [
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 24,
              offset: Offset(-4, 0),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header bar
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  const Text(
                    'My Profile',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: widget.onClose,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 32, minHeight: 32),
                    tooltip: 'Close',
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
            const Divider(height: 1, thickness: 1, color: AppColors.border),
            // Body
            Expanded(
              child: profileAsync.when(
                loading: () => const Center(
                    child: CircularProgressIndicator(strokeWidth: 2)),
                error: (e, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline,
                            color: AppColors.error, size: 32),
                        const SizedBox(height: 12),
                        const Text('Failed to load profile'),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: () =>
                              ref.invalidate(vendorProfileProvider),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ),
                data: (profile) => profile == null
                    ? const Center(child: Text('Profile not found'))
                    : _buildBody(context, profile),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, VendorProfile profile) {
    final initials = _initials(profile.businessName);
    final imageUrl = profile.profileImageUrl;
    final activeColor =
        profile.isActive ? AppColors.success : AppColors.error;

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 16),
      children: [
        // ── Compact avatar + identity ─────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          child: Row(
            children: [
              Tooltip(
                message: 'Change photo',
                child: GestureDetector(
                  onTap: _uploading ? null : _pickAndUpload,
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: AppColors.primaryLight,
                        backgroundImage: imageUrl != null
                            ? NetworkImage(imageUrl)
                            : null,
                        child: imageUrl == null
                            ? Text(
                                initials,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary,
                                ),
                              )
                            : null,
                      ),
                      if (_uploading)
                        const Positioned.fill(
                          child: CircleAvatar(
                            radius: 28,
                            backgroundColor: Colors.black45,
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: AppColors.border, width: 1),
                          ),
                          child: const Icon(
                            Icons.camera_alt_rounded,
                            size: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.businessName,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (profile.ownerName != null &&
                        profile.ownerName!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        profile.ownerName!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: activeColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: activeColor.withValues(alpha: 0.5)),
                      ),
                      child: Text(
                        profile.status.toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: activeColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const Divider(height: 1, thickness: 1, color: AppColors.border),
        const SizedBox(height: 4),

        // ── Info rows ─────────────────────────────────────────────────────
        _PanelInfoRow(
          icon: Icons.phone_outlined,
          label: 'Phone',
          value: profile.phone,
        ),
        if (profile.email != null)
          _PanelInfoRow(
            icon: Icons.email_outlined,
            label: 'Email',
            value: profile.email!,
          ),
        if (profile.city != null)
          _PanelInfoRow(
            icon: Icons.location_city_outlined,
            label: 'City',
            value: profile.city!,
          ),
        if (profile.rating != null)
          _PanelInfoRow(
            icon: Icons.star_outline_rounded,
            label: 'Rating',
            value: '${profile.rating!.toStringAsFixed(1)} / 5.0',
          ),
        _PanelInfoRow(
          icon: Icons.account_balance_wallet_outlined,
          label: 'Wallet Balance',
          value: NumberFormat.currency(symbol: '₹', decimalDigits: 2)
              .format(profile.walletBalance),
          onTap: () => _pushRoute(RoutePaths.wallet),
        ),
        const SizedBox(height: 8),
        const Divider(height: 1, thickness: 1, color: AppColors.border),
        const SizedBox(height: 4),

        // ── Quick actions ──────────────────────────────────────────────────
        _PanelAction(
          icon: Icons.edit_outlined,
          label: 'Edit Profile',
          onTap: () => _navigate(EditProfilePage(profile: profile)),
        ),
        _PanelAction(
          icon: Icons.description_outlined,
          label: 'My Documents',
          onTap: () => _pushRoute(RoutePaths.documents),
        ),
        _PanelAction(
          icon: Icons.workspace_premium_rounded,
          label: 'Subscription',
          onTap: () => _pushRoute(RoutePaths.subscription),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
}

class _PanelInfoRow extends StatelessWidget {
  const _PanelInfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.textSecondary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            if (onTap != null)
              const Icon(Icons.chevron_right_rounded,
                  size: 16, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}

class _PanelAction extends StatelessWidget {
  const _PanelAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, size: 20, color: AppColors.textSecondary),
      title: Text(
        label,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
      trailing: const Icon(Icons.chevron_right_rounded,
          size: 18, color: AppColors.textSecondary),
      onTap: onTap,
      dense: true,
    );
  }
}
