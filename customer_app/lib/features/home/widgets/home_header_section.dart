import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../auth/providers/auth_provider.dart';
import '../../profile/services/profile_providers.dart';

/// Top navigation bar matching the DODO Booker web landing design.
///
/// Desktop: Logo | Services / Service Areas nav + search pill | Get App + chat + avatar
/// Mobile:  Logo | avatar
class HomeHeaderSection extends ConsumerWidget {
  const HomeHeaderSection({super.key, this.padding});

  // Retained for call-site compatibility; ignored — section owns its padding.
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAuth = ref.watch(isAuthenticatedProvider);
    String initials = '';
    if (isAuth) {
      ref.watch(profileProvider).whenData((p) {
        final parts = p.fullName.trim().split(' ');
        initials = parts
            .where((w) => w.isNotEmpty)
            .map((w) => w[0].toUpperCase())
            .take(2)
            .join();
      });
    }

    final w = MediaQuery.sizeOf(context).width;
    // clamp(24px, 4vw, 64px)
    final hPad = (w * 0.04).clamp(24.0, 64.0);
    final isDesktop = w >= 768;

    return ColoredBox(
      color: const Color(0xFF111111),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 16),
        child: isDesktop
            ? _DesktopNav(initials: initials, isAuth: isAuth)
            : _MobileNav(initials: initials, isAuth: isAuth),
      ),
    );
  }
}

// ── Desktop nav ───────────────────────────────────────────────────────────────

class _DesktopNav extends StatelessWidget {
  final String initials;
  final bool isAuth;

  const _DesktopNav({required this.initials, required this.isAuth});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const _Logo(),
        const SizedBox(width: 28),
        _NavLink(label: 'Services ▾', onTap: () => context.push('/categories')),
        const SizedBox(width: 24),
        _NavLink(label: 'Service Areas ▾', onTap: () {}),
        const SizedBox(width: 16),
        Flexible(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400, minWidth: 160),
            child: _SearchPill(onTap: () => context.push('/categories')),
          ),
        ),
        const SizedBox(width: 16),
        const _GetAppButton(),
        const SizedBox(width: 14),
        const _ChatIcon(),
        const SizedBox(width: 14),
        _AvatarButton(initials: initials, isAuth: isAuth),
      ],
    );
  }
}

// ── Mobile nav ────────────────────────────────────────────────────────────────

class _MobileNav extends StatelessWidget {
  final String initials;
  final bool isAuth;

  const _MobileNav({required this.initials, required this.isAuth});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const _Logo(),
        const Spacer(),
        _AvatarButton(initials: initials, isAuth: isAuth),
      ],
    );
  }
}

// ── Logo + wordmark ───────────────────────────────────────────────────────────

class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: const Color(0xFF1E1B17),
            border: Border.all(color: const Color(0xFF2A2622)),
            borderRadius: BorderRadius.circular(100),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(100),
            child: Image.asset(
              'assets/images/logo.png',
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const Center(
                child: Text('🦆', style: TextStyle(fontSize: 18)),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          'DODO\nBOOKER',
          style: GoogleFonts.poppins(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            height: 1.15,
          ),
        ),
      ],
    );
  }
}

// ── Nav link ──────────────────────────────────────────────────────────────────

class _NavLink extends StatefulWidget {
  final String label;
  final VoidCallback onTap;

  const _NavLink({required this.label, required this.onTap});

  @override
  State<_NavLink> createState() => _NavLinkState();
}

class _NavLinkState extends State<_NavLink> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Text(
          widget.label,
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: _hovered ? AppColors.gold : const Color(0xFFEDEAE4),
          ),
        ),
      ),
    );
  }
}

// ── Search pill ───────────────────────────────────────────────────────────────

class _SearchPill extends StatefulWidget {
  final VoidCallback? onTap;
  const _SearchPill({this.onTap});

  @override
  State<_SearchPill> createState() => _SearchPillState();
}

class _SearchPillState extends State<_SearchPill> {
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
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1B17),
            borderRadius: BorderRadius.circular(100),
            border: Border.all(
              color: _hovered
                  ? const Color(0xFF3A3530)
                  : const Color(0xFF2A2622),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.search_rounded,
                size: 15,
                color: Color(0xFF7A756D),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Search for services…',
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: const Color(0xFF7A756D),
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

// ── Get App button ────────────────────────────────────────────────────────────

class _GetAppButton extends StatefulWidget {
  const _GetAppButton();

  @override
  State<_GetAppButton> createState() => _GetAppButtonState();
}

class _GetAppButtonState extends State<_GetAppButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () {},
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            color: _hovered
                ? const Color(0xFF2A2622)
                : const Color(0xFF1E1B17),
            borderRadius: BorderRadius.circular(100),
            border: Border.all(color: const Color(0xFF2A2622)),
          ),
          child: Text(
            'Get App',
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Chat icon ─────────────────────────────────────────────────────────────────

class _ChatIcon extends StatelessWidget {
  const _ChatIcon();

  @override
  Widget build(BuildContext context) {
    return const Icon(
      Icons.chat_bubble_outline_rounded,
      size: 18,
      color: Color(0xFFEDEAE4),
    );
  }
}

// ── Avatar button ─────────────────────────────────────────────────────────────

class _AvatarButton extends StatelessWidget {
  final String initials;
  final bool isAuth;

  const _AvatarButton({required this.initials, required this.isAuth});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/profile'),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.gold, width: 1.5),
          ),
          child: ClipOval(
            child: Container(
              color: const Color(0xFF1E1B17),
              alignment: Alignment.center,
              child: initials.isNotEmpty
                  ? Text(
                      initials,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.gold,
                      ),
                    )
                  : const Icon(
                      Icons.person_outline_rounded,
                      size: 18,
                      color: Color(0xFFEDEAE4),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
