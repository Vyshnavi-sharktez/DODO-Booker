import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../auth/utils/auth_modal_gate.dart';
import '../screens/instahelp_vendor_list_screen.dart';
import 'instahelp_location_picker.dart';

class InstaHelpHomeTile extends ConsumerWidget {
  const InstaHelpHomeTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isWide = MediaQuery.sizeOf(context).width >= 768;
    return isWide ? const _WebLayout() : const _MobileLayout();
  }
}

// ── Shared colors ─────────────────────────────────────────────────────────────

const _kBg1 = Color(0xFFFFF8E7);
const _kBg2 = Color(0xFFFFF0C2);
const _kBadgeBg = Color(0xFFFFF3CD);
const _kBadgeText = Color(0xFFD98A0A);

// ── Shared: open address picker then push vendor list ─────────────────────────

Future<void> _openFlow(BuildContext context, WidgetRef ref, int initialTab) async {
  final authed = await requireAuth(context, ref);
  if (!authed || !context.mounted) return;

  final location = await InstaHelpLocationPicker.show(context);
  if (location == null || !context.mounted) return;

  Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => InstaHelpVendorListScreen(
        lat: location.lat,
        lng: location.lng,
        initialTab: initialTab,
      ),
    ),
  );
}

// ── Web layout ────────────────────────────────────────────────────────────────

class _WebLayout extends StatelessWidget {
  const _WebLayout();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 32, vertical: 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_kBg1, _kBg2],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFFEBC351),
          width: 2.0,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFD98A0A).withValues(alpha: 0.12),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            Positioned(
              right: 20,
              top: -10,
              child: Icon(
                Icons.flash_on_rounded,
                size: 180,
                color: AppColors.gold.withValues(alpha: 0.08),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 28, 32, 28),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    flex: 6,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _BadgeChip(),
                        const SizedBox(height: 10),
                        Text(
                          'Book a House Help',
                          style: GoogleFonts.poppins(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Professional assistance for your daily needs',
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Expanded(
                                child: _ModeCard(
                                    tabIndex: 0,
                                    icon: Icons.calendar_today_rounded,
                                    title: 'Schedule',
                                    subtitle: 'Book a time slot')),
                            const SizedBox(width: 10),
                            Expanded(
                                child: _ModeCard(
                                    tabIndex: 1,
                                    icon: Icons.flash_on_rounded,
                                    title: 'Instant',
                                    subtitle: 'Get help right now')),
                            const SizedBox(width: 10),
                            Expanded(
                                child: _ModeCard(
                                    tabIndex: 2,
                                    icon: Icons.local_car_wash_rounded,
                                    title: 'Car Wash',
                                    subtitle: 'On-demand car cleaning')),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: _Illustration(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Mobile layout ─────────────────────────────────────────────────────────────

class _MobileLayout extends StatelessWidget {
  const _MobileLayout();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_kBg1, _kBg2],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFEBC351),
          width: 2.0,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFD98A0A).withValues(alpha: 0.1),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          children: [
            Positioned(
              right: -10,
              top: -10,
              child: Icon(
                Icons.flash_on_rounded,
                size: 120,
                color: AppColors.gold.withValues(alpha: 0.07),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _BadgeChip(),
                            const SizedBox(height: 8),
                            Text(
                              'Book a House Help',
                              style: GoogleFonts.poppins(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: AppColors.primary,
                                height: 1.2,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Get reliable household assistance\nfor your daily needs',
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      _Illustration(size: 80),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                          child: _ModeCard(
                              tabIndex: 0,
                              icon: Icons.calendar_today_rounded,
                              title: 'Schedule',
                              subtitle: 'Book a slot')),
                      const SizedBox(width: 8),
                      Expanded(
                          child: _ModeCard(
                              tabIndex: 1,
                              icon: Icons.flash_on_rounded,
                              title: 'Instant',
                              subtitle: 'Right now')),
                      const SizedBox(width: 8),
                      Expanded(
                          child: _ModeCard(
                              tabIndex: 2,
                              icon: Icons.local_car_wash_rounded,
                              title: 'Car Wash',
                              subtitle: 'On demand')),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Shared sub-widgets ────────────────────────────────────────────────────────

class _BadgeChip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _kBadgeBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.flash_on_rounded, size: 13, color: _kBadgeText),
          const SizedBox(width: 4),
          Text(
            'InstaHelp',
            style: GoogleFonts.poppins(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: _kBadgeText,
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeCard extends ConsumerStatefulWidget {
  final int tabIndex;
  final IconData icon;
  final String title;
  final String subtitle;

  const _ModeCard({
    required this.tabIndex,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  ConsumerState<_ModeCard> createState() => _ModeCardState();
}

class _ModeCardState extends ConsumerState<_ModeCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final tabIndex = widget.tabIndex;
    final isInstant = tabIndex == 1;
    final isCarWash = tabIndex == 2;
    final Color iconBg = isCarWash
        ? const Color(0xFFE0F2FE)
        : isInstant
            ? AppColors.gold.withValues(alpha: 0.12)
            : const Color(0xFFEEF2FF);
    final Color iconColor = isCarWash
        ? const Color(0xFF0284C7)
        : isInstant
            ? _kBadgeText
            : const Color(0xFF4F6DFF);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () => _openFlow(context, ref, tabIndex),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: _hovered
                ? Border.all(color: AppColors.gold, width: 1.5)
                : Border.all(color: Colors.transparent, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: _hovered ? 0.11 : 0.07),
                blurRadius: _hovered ? 16 : 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(widget.icon, size: 18, color: iconColor),
            ),
            const SizedBox(height: 8),
            Text(
              widget.title,
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            Text(
              widget.subtitle,
              style: GoogleFonts.poppins(
                fontSize: 10,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }
}

class _Illustration extends StatelessWidget {
  final double size;
  const _Illustration({this.size = 120});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.gold.withValues(alpha: 0.15),
        shape: BoxShape.circle,
      ),
      child: Icon(
        Icons.home_repair_service_rounded,
        size: size * 0.5,
        color: AppColors.goldDeep,
      ),
    );
  }
}
