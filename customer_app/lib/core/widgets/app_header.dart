import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../constants/app_colors.dart';
import 'app_modal_dialog.dart';
import 'pwa_install_dialog.dart';
import '../../features/notifications/widgets/notifications_modal.dart';
import '../../features/notifications/services/notification_providers.dart';
import '../../features/profile/services/profile_providers.dart';
import '../../features/cart/providers/cart_provider.dart';
import '../../features/cart/utils/cart_launcher.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/auth/utils/auth_modal_gate.dart';
import '../../features/loyalty/providers/loyalty_providers.dart';
import '../../features/catalog/providers/catalog_providers.dart';
import '../../features/catalog/models/catalog_node_model.dart';
import '../../features/catalog/utils/catalog_launcher.dart';
import '../../features/service_areas/providers/service_areas_providers.dart';
import '../../features/wishlist/screens/wishlist_screen.dart';
import 'nav_search.dart';
import 'page_sheet.dart';

/// Persistent DODO BOOKER header. Implements [PreferredSizeWidget].
class AppHeader extends ConsumerWidget implements PreferredSizeWidget {
  final VoidCallback onLogoTap;
  final VoidCallback onProfileTap;
  final bool isScrolled;

  const AppHeader({
    super.key,
    required this.onLogoTap,
    required this.onProfileTap,
    this.isScrolled = false,
  });

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = width >= 1024;
    final isWide = width >= 768;

    return Material(
      color: Colors.transparent,
      elevation: 0,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          boxShadow: isScrolled
              ? [
                  BoxShadow(
                    color: Colors.black.withAlpha(18),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  )
                ]
              : const [],
        ),
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: SafeArea(
              bottom: false,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                height: 64,
                decoration: BoxDecoration(
                  color: const Color(0xFF111111),
                  border: Border(
                    bottom: BorderSide(
                      color: Colors.white.withAlpha(isScrolled ? 30 : 18),
                      width: 0.8,
                    ),
                  ),
                ),
                child: Align(
                  alignment: Alignment.center,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1440),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: isDesktop
                          ? _DesktopRow(
                              onLogoTap: onLogoTap,
                              onProfileTap: onProfileTap)
                          : isWide
                              ? _WideRow(
                                  onLogoTap: onLogoTap,
                                  onProfileTap: onProfileTap)
                              : _MobileRow(
                                  onLogoTap: onLogoTap,
                                  onProfileTap: onProfileTap),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Row layouts
// ─────────────────────────────────────────────────────────────────────────────

// Desktop (>=1024px): Logo | Services▼ | Service Areas▼ | Search | GetApp | Utility

class _DesktopRow extends StatelessWidget {
  final VoidCallback onLogoTap;
  final VoidCallback onProfileTap;
  const _DesktopRow({required this.onLogoTap, required this.onProfileTap});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: onLogoTap,
            behavior: HitTestBehavior.opaque,
            child: const _DodoBrand(),
          ),
        ),
        const SizedBox(width: 16),

        // Nav dropdowns
        _NavDropdownAnchor(
          label: 'Services',
          alignRight: false,
          contentBuilder: (close) => _ServicesDropdownPanel(close: close),
        ),
        const SizedBox(width: 2),
        _NavDropdownAnchor(
          label: 'Service Areas',
          alignRight: false,
          contentBuilder: (close) => _ServiceAreasDropdownPanel(close: close),
        ),
        const SizedBox(width: 12),

        // Search
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: const NavSearchBar(),
            ),
          ),
        ),
        const SizedBox(width: 12),

        // Download App
        const _DownloadAppButton(),
        const SizedBox(width: 10),

        // Utility
        const _LoyaltyPill(),
        const SizedBox(width: 8),
        const _WishlistButton(),
        const SizedBox(width: 8),
        _NotifButton(onTap: () {
          debugPrint(
              '[DODO][Notif] tap fired — ${DateTime.now().millisecondsSinceEpoch}ms');
          AppModalDialog.show(
              context: context, child: const NotificationsModal());
        }),
        const SizedBox(width: 8),
        const _CartButton(),
        const SizedBox(width: 8),
        _ProfileAvatar(onTap: onProfileTap),
      ],
    );
  }
}

// Tablet (768–1023px): Logo | Search | Services▼ | ServiceAreas▼ | Utility

class _WideRow extends StatelessWidget {
  final VoidCallback onLogoTap;
  final VoidCallback onProfileTap;
  const _WideRow({required this.onLogoTap, required this.onProfileTap});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: onLogoTap,
            behavior: HitTestBehavior.opaque,
            child: const _DodoBrand(),
          ),
        ),
        const SizedBox(width: 16),

        // Search
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: const NavSearchBar(),
            ),
          ),
        ),
        const SizedBox(width: 8),

        // Nav dropdowns (right-aligned so panels don't clip off-screen)
        _NavDropdownAnchor(
          label: 'Services',
          alignRight: true,
          contentBuilder: (close) => _ServicesDropdownPanel(close: close),
        ),
        const SizedBox(width: 2),
        _NavDropdownAnchor(
          label: 'Service Areas',
          alignRight: true,
          contentBuilder: (close) => _ServiceAreasDropdownPanel(close: close),
        ),
        const SizedBox(width: 8),

        // Utility
        const _LoyaltyPill(),
        const SizedBox(width: 8),
        const _WishlistButton(),
        const SizedBox(width: 8),
        _NotifButton(onTap: () {
          debugPrint(
              '[DODO][Notif] tap fired — ${DateTime.now().millisecondsSinceEpoch}ms');
          AppModalDialog.show(
              context: context, child: const NotificationsModal());
        }),
        const SizedBox(width: 8),
        const _CartButton(),
        const SizedBox(width: 8),
        _ProfileAvatar(onTap: onProfileTap),
      ],
    );
  }
}

// Mobile (<768px): Logo | Spacer | Loyalty | Search | Cart | Notif | ☰ | Profile

class _MobileRow extends StatelessWidget {
  final VoidCallback onLogoTap;
  final VoidCallback onProfileTap;
  const _MobileRow({required this.onLogoTap, required this.onProfileTap});

  void _showMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => _MobileNavSheet(parentContext: context),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: onLogoTap,
            behavior: HitTestBehavior.opaque,
            child: const _DodoBrand(),
          ),
        ),
        const Spacer(),
        const _LoyaltyPill(),
        const SizedBox(width: 4),
        const NavSearchButton(),
        const SizedBox(width: 4),
        const _CartButton(),
        const SizedBox(width: 4),
        const _WishlistButton(),
        const SizedBox(width: 4),
        _NotifButton(onTap: () {
          debugPrint(
              '[DODO][Notif] tap fired — ${DateTime.now().millisecondsSinceEpoch}ms');
          AppModalDialog.show(
              context: context, child: const NotificationsModal());
        }),
        const SizedBox(width: 4),
        _HeaderIconBtn(
          icon: Icons.menu_rounded,
          onTap: () => _showMenu(context),
        ),
        const SizedBox(width: 6),
        _ProfileAvatar(onTap: onProfileTap),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Nav Dropdown Anchor — click-only toggle, no hover open/close
// ─────────────────────────────────────────────────────────────────────────────

class _NavDropdownAnchor extends StatefulWidget {
  final String label;
  final bool alignRight;
  final Widget Function(VoidCallback close) contentBuilder;

  const _NavDropdownAnchor({
    required this.label,
    required this.alignRight,
    required this.contentBuilder,
  });

  @override
  State<_NavDropdownAnchor> createState() => _NavDropdownAnchorState();
}

class _NavDropdownAnchorState extends State<_NavDropdownAnchor> {
  final LayerLink _link = LayerLink();
  OverlayEntry? _entry;
  bool _open = false;

  @override
  void dispose() {
    _entry?.remove();
    super.dispose();
  }

  void _openDropdown() {
    if (_open) return;
    final entry = OverlayEntry(builder: _buildOverlay);
    Overlay.of(context, rootOverlay: false).insert(entry);
    _entry = entry;
    if (mounted) setState(() => _open = true);
  }

  void _close() {
    _entry?.remove();
    _entry = null;
    if (mounted) setState(() => _open = false);
  }

  void _toggle() => _open ? _close() : _openDropdown();

  Widget _buildOverlay(BuildContext ctx) {
    final targetAnchor =
        widget.alignRight ? Alignment.bottomRight : Alignment.bottomLeft;
    final followerAnchor =
        widget.alignRight ? Alignment.topRight : Alignment.topLeft;

    return Stack(
      children: [
        // Transparent barrier — catches taps outside the panel
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _close,
          ),
        ),
        // Dropdown panel — higher Z-order, absorbs its own taps before barrier
        CompositedTransformFollower(
          link: _link,
          showWhenUnlinked: false,
          targetAnchor: targetAnchor,
          followerAnchor: followerAnchor,
          offset: const Offset(0, 8),
          child: Material(
            elevation: 24,
            shadowColor: Colors.black.withAlpha(36),
            borderRadius: BorderRadius.circular(16),
            color: Colors.transparent,
            child: widget.contentBuilder(_close),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: _toggle,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _open ? Colors.white.withAlpha(18) : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.label,
                  style: GoogleFonts.inter(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                    color: _open
                        ? Colors.white
                        : const Color(0xFFEDEAE4),
                  ),
                ),
                const SizedBox(width: 2),
                AnimatedRotation(
                  turns: _open ? 0.5 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 16,
                    color: _open
                        ? Colors.white
                        : const Color(0xFFEDEAE4),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Services Dropdown Panel
// ─────────────────────────────────────────────────────────────────────────────

class _ServicesDropdownPanel extends ConsumerWidget {
  final VoidCallback close;
  const _ServicesDropdownPanel({required this.close});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nodesAsync = ref.watch(rootCatalogNodesProvider);

    return Container(
      width: 240,
      constraints: const BoxConstraints(maxHeight: 380),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 0.8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Panel header
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
            child: Row(
              children: [
                Container(
                  width: 5,
                  height: 16,
                  decoration: BoxDecoration(
                    color: AppColors.gold,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Our Services',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),

          // Content
          Flexible(
            child: nodesAsync.when(
              loading: () => const _PanelSkeleton(itemCount: 6),
              error: (e, _) => const _PanelError(message: 'Could not load services'),
              data: (nodes) {
                final active = nodes
                    .where((n) =>
                        n.isActive && n.availabilityStatus != 'hidden')
                    .toList();
                if (active.isEmpty) {
                  return const _PanelEmpty(message: 'No services available');
                }
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: active
                        .map((n) => Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: _ServiceChip(
                                node: n,
                                onTap: () {
                                  close();
                                  openCatalogNode(context, n);
                                },
                              ),
                            ))
                        .toList(),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Service Areas Dropdown Panel
// ─────────────────────────────────────────────────────────────────────────────

class _ServiceAreasDropdownPanel extends ConsumerWidget {
  final VoidCallback close;
  const _ServiceAreasDropdownPanel({required this.close});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final areasAsync = ref.watch(serviceAreasProvider);

    return Container(
      width: 300,
      constraints: const BoxConstraints(maxHeight: 380),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 0.8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Panel header
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
            child: Row(
              children: [
                Container(
                  width: 5,
                  height: 16,
                  decoration: BoxDecoration(
                    color: AppColors.gold,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Where We Serve',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),

          // Content
          Flexible(
            child: areasAsync.when(
              loading: () => const _PanelSkeleton(itemCount: 4),
              error: (e, _) => const _PanelError(message: 'Could not load areas'),
              data: (areas) {
                if (areas.isEmpty) {
                  return const _PanelEmpty(message: 'Coming soon');
                }
                // Group by city
                final Map<String, List<ServiceAreaModel>> byCity = {};
                for (final a in areas) {
                  byCity.putIfAbsent(a.city, () => []).add(a);
                }
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: byCity.entries
                        .map((e) => _CityGroup(
                              city: e.key,
                              areas: e.value,
                            ))
                        .toList(),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Service chip (used in Services panel)
// ─────────────────────────────────────────────────────────────────────────────

class _ServiceChip extends StatefulWidget {
  final CatalogNodeModel node;
  final VoidCallback onTap;
  const _ServiceChip({required this.node, required this.onTap});

  @override
  State<_ServiceChip> createState() => _ServiceChipState();
}

class _ServiceChipState extends State<_ServiceChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color:
                _hovered ? AppColors.goldLight : AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _hovered
                  ? AppColors.gold.withAlpha(140)
                  : AppColors.border,
              width: _hovered ? 1.4 : 0.8,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.home_repair_service_rounded,
                size: 15,
                color:
                    _hovered ? AppColors.gold : AppColors.textSecondary,
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  widget.node.name,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _hovered
                        ? AppColors.textPrimary
                        : AppColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (widget.node.hasChildren) ...[
                const SizedBox(width: 4),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 10,
                  color: AppColors.textHint,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// City group (used in Service Areas panel)
// ─────────────────────────────────────────────────────────────────────────────

class _CityGroup extends StatelessWidget {
  final String city;
  final List<ServiceAreaModel> areas;
  const _CityGroup({required this.city, required this.areas});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.location_city_rounded,
                  size: 13, color: AppColors.gold),
              const SizedBox(width: 5),
              Text(
                city,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: areas
                .map((a) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceVariant,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color: AppColors.border, width: 0.6),
                        ),
                        child: Text(
                          a.name,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dropdown shared helpers
// ─────────────────────────────────────────────────────────────────────────────

class _PanelSkeleton extends StatelessWidget {
  final int itemCount;
  const _PanelSkeleton({required this.itemCount});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: List.generate(
          itemCount,
          (_) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Container(
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.shimmerBase,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PanelError extends StatelessWidget {
  final String message;
  const _PanelError({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Text(
          message,
          style: const TextStyle(
              fontSize: 13, color: AppColors.textSecondary),
        ),
      ),
    );
  }
}

class _PanelEmpty extends StatelessWidget {
  final String message;
  const _PanelEmpty({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Text(
          message,
          style: const TextStyle(
              fontSize: 13, color: AppColors.textSecondary),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Mobile nav sheet (hamburger menu)
// ─────────────────────────────────────────────────────────────────────────────

class _MobileNavSheet extends ConsumerWidget {
  final BuildContext parentContext;
  const _MobileNavSheet({required this.parentContext});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nodesAsync = ref.watch(rootCatalogNodesProvider);
    final areasAsync = ref.watch(serviceAreasProvider);

    final activeNodes = nodesAsync.asData?.value
            .where((n) => n.isActive && n.availabilityStatus != 'hidden')
            .toList() ??
        [];

    final areas = areasAsync.asData?.value ?? [];
    final Map<String, List<ServiceAreaModel>> byCity = {};
    for (final a in areas) {
      byCity.putIfAbsent(a.city, () => []).add(a);
    }

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, scrollController) => Column(
        children: [
          // Drag handle
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          Expanded(
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(0, 0, 0, 24),
              children: [
                // ── Services ───────────────────────────────────────────────
                _SheetSectionHeader(
                  icon: Icons.home_repair_service_rounded,
                  label: 'Services',
                ),
                if (nodesAsync.isLoading)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                else if (activeNodes.isEmpty)
                  const _SheetEmptyHint('No services available')
                else
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: activeNodes
                          .map((n) => _MobileServiceChip(
                                node: n,
                                onTap: () {
                                  Navigator.pop(context);
                                  openCatalogNode(parentContext, n);
                                },
                              ))
                          .toList(),
                    ),
                  ),

                const Divider(color: AppColors.border, height: 24),

                // ── Service Areas ──────────────────────────────────────────
                _SheetSectionHeader(
                  icon: Icons.location_on_rounded,
                  label: 'Service Areas',
                ),
                if (areasAsync.isLoading)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                else if (byCity.isEmpty)
                  const _SheetEmptyHint('Coming soon')
                else
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: byCity.entries
                          .map((e) => _MobileCityGroup(
                                city: e.key,
                                areas: e.value,
                              ))
                          .toList(),
                    ),
                  ),

                const Divider(color: AppColors.border, height: 24),

                // ── Install App ───────────────────────────────────────────
                _SheetSectionHeader(
                  icon: Icons.download_rounded,
                  label: 'Install App',
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: _MobileInstallButton(parentContext: parentContext),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetSectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  const _SheetSectionHeader({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.gold),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetEmptyHint extends StatelessWidget {
  final String text;
  const _SheetEmptyHint(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Text(
        text,
        style: const TextStyle(fontSize: 13, color: AppColors.textHint),
      ),
    );
  }
}

class _MobileServiceChip extends StatelessWidget {
  final CatalogNodeModel node;
  final VoidCallback onTap;
  const _MobileServiceChip({required this.node, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border, width: 0.8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.home_repair_service_rounded,
                size: 14, color: AppColors.textSecondary),
            const SizedBox(width: 6),
            Text(
              node.name,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileCityGroup extends StatelessWidget {
  final String city;
  final List<ServiceAreaModel> areas;
  const _MobileCityGroup({required this.city, required this.areas});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.location_city_rounded,
                  size: 13, color: AppColors.gold),
              const SizedBox(width: 5),
              Text(
                city,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Wrap(
            spacing: 6,
            runSpacing: 5,
            children: areas
                .map((a) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceVariant,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: AppColors.border, width: 0.6),
                      ),
                      child: Text(
                        a.name,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _MobileInstallButton extends StatelessWidget {
  final BuildContext parentContext;
  const _MobileInstallButton({required this.parentContext});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.pop(context);
        PwaInstallDialog.show(parentContext);
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.textPrimary,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.download_rounded, color: Colors.white, size: 18),
            SizedBox(width: 10),
            Text(
              'Install DODO',
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Download App button (desktop)
// ─────────────────────────────────────────────────────────────────────────────

class _DownloadAppButton extends StatefulWidget {
  const _DownloadAppButton();

  @override
  State<_DownloadAppButton> createState() => _DownloadAppButtonState();
}

class _DownloadAppButtonState extends State<_DownloadAppButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () => PwaInstallDialog.show(context),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: _hovered ? AppColors.goldDeep : AppColors.gold,
            borderRadius: BorderRadius.circular(100),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.download_rounded, size: 15, color: AppColors.primary),
              const SizedBox(width: 6),
              Text(
                'Get App',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DODO brand
// ─────────────────────────────────────────────────────────────────────────────

class _DodoBrand extends StatelessWidget {
  const _DodoBrand();

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final h = w >= 1024 ? 34.0 : w >= 768 ? 28.0 : 24.0;
    return Image.asset(
      'assets/images/logo.png',
      height: h,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      errorBuilder: (ctx, e, _) => const _FallbackBrand(),
    );
  }
}

class _FallbackBrand extends StatelessWidget {
  const _FallbackBrand();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.textPrimary,
            borderRadius: BorderRadius.circular(9),
          ),
          child: const Icon(Icons.home_repair_service_rounded,
              color: AppColors.gold, size: 18),
        ),
        const SizedBox(width: 9),
        RichText(
          text: const TextSpan(
            children: [
              TextSpan(
                text: 'DODO',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8),
              ),
              TextSpan(
                text: ' BOOKER',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.3),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ─────────────────────────────────────────────────────────────────────────────
// Notification button
// ─────────────────────────────────────────────────────────────────────────────

class _NotifButton extends ConsumerStatefulWidget {
  final VoidCallback onTap;
  const _NotifButton({required this.onTap});

  @override
  ConsumerState<_NotifButton> createState() => _NotifButtonState();
}

class _NotifButtonState extends ConsumerState<_NotifButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(isAuthenticatedProvider)) return const SizedBox.shrink();
    final unread = ref.watch(unreadCountProvider);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: _hovered
                ? Colors.white.withAlpha(28)
                : Colors.white.withAlpha(14),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _hovered
                  ? Colors.white.withAlpha(80)
                  : Colors.white.withAlpha(35),
              width: 0.8,
            ),
          ),
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              Icon(Icons.notifications_outlined,
                  size: 20,
                  color: _hovered ? AppColors.gold : Colors.white.withAlpha(220)),
              if (unread > 0)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                        color: AppColors.error, shape: BoxShape.circle),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Wishlist button
// ─────────────────────────────────────────────────────────────────────────────

class _WishlistButton extends ConsumerStatefulWidget {
  const _WishlistButton();

  @override
  ConsumerState<_WishlistButton> createState() => _WishlistButtonState();
}

class _WishlistButtonState extends ConsumerState<_WishlistButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(isAuthenticatedProvider)) return const SizedBox.shrink();
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () {
          if (MediaQuery.sizeOf(context).width >= 768) {
            PageSheet.show(context,
                title: 'Wishlist',
                child: const WishlistScreen(inModal: true));
          } else {
            context.push('/wishlist');
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: _hovered
                ? Colors.white.withAlpha(28)
                : Colors.white.withAlpha(14),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _hovered
                  ? Colors.white.withAlpha(80)
                  : Colors.white.withAlpha(35),
              width: 0.8,
            ),
          ),
          child: Icon(
            Icons.favorite_border_rounded,
            size: 20,
            color: _hovered ? AppColors.gold : Colors.white.withAlpha(220),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Cart button
// ─────────────────────────────────────────────────────────────────────────────

class _CartButton extends ConsumerStatefulWidget {
  const _CartButton();

  @override
  ConsumerState<_CartButton> createState() => _CartButtonState();
}

class _CartButtonState extends ConsumerState<_CartButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final count = ref.watch(cartItemCountProvider);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () {
          ScaffoldMessenger.of(context).clearSnackBars();
          openCart(context);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: _hovered
                ? Colors.white.withAlpha(28)
                : Colors.white.withAlpha(14),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _hovered
                  ? Colors.white.withAlpha(80)
                  : Colors.white.withAlpha(35),
              width: 0.8,
            ),
          ),
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              Icon(Icons.shopping_cart_outlined,
                  size: 20,
                  color: _hovered ? AppColors.gold : Colors.white.withAlpha(220)),
              if (count > 0)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: const BoxDecoration(
                        color: AppColors.error, shape: BoxShape.circle),
                    child: Center(
                      child: Text(
                        count > 9 ? '9+' : '$count',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            height: 1),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Loyalty pill
// ─────────────────────────────────────────────────────────────────────────────

class _LoyaltyPill extends ConsumerWidget {
  const _LoyaltyPill();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(isAuthenticatedProvider)) return const SizedBox.shrink();
    final points =
        ref.watch(customerLoyaltyProvider).whenOrNull(data: (l) => l.availablePoints);
    if (points == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: const Color(0xFFFFD700).withAlpha(100), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.stars_rounded,
              size: 14, color: Color(0xFFFFD700)),
          const SizedBox(width: 4),
          Text(
            '$points',
            style: const TextStyle(
                color: Color(0xFFFFD700),
                fontSize: 12,
                fontWeight: FontWeight.w700,
                height: 1),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Small icon button (mobile)
// ─────────────────────────────────────────────────────────────────────────────

class _HeaderIconBtn extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _HeaderIconBtn({required this.icon, required this.onTap});

  @override
  State<_HeaderIconBtn> createState() => _HeaderIconBtnState();
}

class _HeaderIconBtnState extends State<_HeaderIconBtn> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: _hovered
                ? Colors.white.withAlpha(28)
                : Colors.white.withAlpha(14),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _hovered
                  ? Colors.white.withAlpha(80)
                  : Colors.white.withAlpha(35),
              width: 0.8,
            ),
          ),
          child: Icon(
            widget.icon,
            size: 20,
            color: _hovered ? AppColors.gold : Colors.white.withAlpha(220),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Profile avatar
// ─────────────────────────────────────────────────────────────────────────────

class _ProfileAvatar extends ConsumerStatefulWidget {
  final VoidCallback onTap;
  const _ProfileAvatar({required this.onTap});

  @override
  ConsumerState<_ProfileAvatar> createState() => _ProfileAvatarState();
}

class _ProfileAvatarState extends ConsumerState<_ProfileAvatar> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isAuth = ref.watch(isAuthenticatedProvider);
    final initials = isAuth
        ? ref.watch(profileProvider).when(
            data: (p) => p.initials,
            loading: () => '',
            error: (e, _) => '')
        : '';

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: isAuth ? widget.onTap : () => requireAuth(context, ref),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: AppColors.textPrimary,
            shape: BoxShape.circle,
            border: Border.all(
              color: _hovered
                  ? AppColors.gold
                  : AppColors.gold.withAlpha(80),
              width: _hovered ? 2.0 : 1.5,
            ),
            boxShadow: _hovered
                ? [
                    BoxShadow(
                        color: AppColors.gold.withAlpha(64),
                        blurRadius: 10)
                  ]
                : null,
          ),
          child: initials.isNotEmpty
              ? Center(
                  child: Text(initials,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700)))
              : const Icon(Icons.person_rounded,
                  color: Colors.white, size: 20),
        ),
      ),
    );
  }
}
