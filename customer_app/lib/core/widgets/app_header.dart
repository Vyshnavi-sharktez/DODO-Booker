import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../constants/app_colors.dart';
import 'app_modal_dialog.dart';
import '../../features/notifications/widgets/notifications_modal.dart';
import '../../features/notifications/services/notification_providers.dart';
import '../../features/profile/services/profile_providers.dart';
import '../../features/cart/providers/cart_provider.dart';

/// Persistent DODO BOOKER header used as the [Scaffold.appBar] across the
/// main navigation shell. Implements [PreferredSizeWidget] so Flutter can
/// correctly position the body below it and clear top-padding for children.
class AppHeader extends ConsumerWidget implements PreferredSizeWidget {
  final VoidCallback onLogoTap;
  final VoidCallback onProfileTap;

  const AppHeader({
    super.key,
    required this.onLogoTap,
    required this.onProfileTap,
  });

  @override
  Size get preferredSize => const Size.fromHeight(58);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isWide = MediaQuery.of(context).size.width >= 640;

    return Material(
      color: AppColors.surface,
      elevation: 0,
      child: SafeArea(
        bottom: false,
        child: Container(
          height: 58,
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(
              bottom: BorderSide(color: AppColors.divider, width: 0.8),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: isWide
              ? _WideRow(onLogoTap: onLogoTap, onProfileTap: onProfileTap)
              : _MobileRow(onLogoTap: onLogoTap, onProfileTap: onProfileTap),
        ),
      ),
    );
  }
}

// ── Wide layout (tablet / desktop) ────────────────────────────────────────────

class _WideRow extends StatelessWidget {
  final VoidCallback onLogoTap;
  final VoidCallback onProfileTap;

  const _WideRow({required this.onLogoTap, required this.onProfileTap});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        GestureDetector(
          onTap: onLogoTap,
          behavior: HitTestBehavior.opaque,
          child: const _DodoBrand(),
        ),
        const SizedBox(width: 20),
        const Expanded(child: _GlobalSearchBar()),
        const SizedBox(width: 12),
        _NotifButton(onTap: () => AppModalDialog.show(
          context: context,
          child: const NotificationsModal(),
        )),
        const SizedBox(width: 8),
        const _CartButton(),
        const SizedBox(width: 8),
        _ProfileAvatar(onTap: onProfileTap),
      ],
    );
  }
}

// ── Mobile layout ─────────────────────────────────────────────────────────────

class _MobileRow extends StatelessWidget {
  final VoidCallback onLogoTap;
  final VoidCallback onProfileTap;

  const _MobileRow({required this.onLogoTap, required this.onProfileTap});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        GestureDetector(
          onTap: onLogoTap,
          behavior: HitTestBehavior.opaque,
          child: const _DodoBrand(),
        ),
        const Spacer(),
        _HeaderIconBtn(
          icon: Icons.search_rounded,
          onTap: () {
            // TODO: open search
          },
        ),
        const SizedBox(width: 4),
        const _CartButton(),
        const SizedBox(width: 4),
        _NotifButton(onTap: () => AppModalDialog.show(
          context: context,
          child: const NotificationsModal(),
        )),
        const SizedBox(width: 6),
        _ProfileAvatar(onTap: onProfileTap),
      ],
    );
  }
}

// ── DODO BOOKER brand ─────────────────────────────────────────────────────────

class _DodoBrand extends StatelessWidget {
  const _DodoBrand();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // App icon
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1A73E8), Color(0xFF0D47A1)],
            ),
            borderRadius: BorderRadius.circular(9),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF1A73E8).withAlpha(55),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: const Icon(
            Icons.home_repair_service_rounded,
            color: Colors.white,
            size: 18,
          ),
        ),
        const SizedBox(width: 9),
        RichText(
          text: const TextSpan(
            children: [
              TextSpan(
                text: 'DODO',
                style: TextStyle(
                  color: Color(0xFF1A73E8),
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
              TextSpan(
                text: ' BOOKER',
                style: TextStyle(
                  color: Color(0xFF202124),
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Global search bar (wide layout only) ─────────────────────────────────────

class _GlobalSearchBar extends StatelessWidget {
  const _GlobalSearchBar();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        // TODO: open search
      },
      child: Container(
        height: 38,
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border, width: 0.8),
        ),
        child: Row(
          children: [
            const SizedBox(width: 12),
            const Icon(Icons.search_rounded, size: 18, color: AppColors.textHint),
            const SizedBox(width: 8),
            Text(
              'Search for services...',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textHint,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Notification button ───────────────────────────────────────────────────────

class _NotifButton extends ConsumerWidget {
  final VoidCallback onTap;

  const _NotifButton({required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unreadCount = ref.watch(unreadCountProvider);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border, width: 0.8),
        ),
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            const Icon(
              Icons.notifications_outlined,
              size: 20,
              color: AppColors.textPrimary,
            ),
            if (unreadCount > 0)
              Positioned(
                top: 7,
                right: 7,
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: AppColors.error,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Cart button with badge ────────────────────────────────────────────────────

class _CartButton extends ConsumerWidget {
  const _CartButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(cartItemCountProvider);

    return GestureDetector(
      onTap: () {
        ScaffoldMessenger.of(context).clearSnackBars();
        context.go('/cart');
      },
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border, width: 0.8),
        ),
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            const Icon(
              Icons.shopping_cart_outlined,
              size: 20,
              color: AppColors.textPrimary,
            ),
            if (count > 0)
              Positioned(
                top: 4,
                right: 4,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: const BoxDecoration(
                    color: AppColors.error,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      count > 9 ? '9+' : '$count',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        height: 1,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Small icon button (mobile) ────────────────────────────────────────────────

class _HeaderIconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _HeaderIconBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border, width: 0.8),
        ),
        child: Icon(icon, size: 20, color: AppColors.textPrimary),
      ),
    );
  }
}

// ── Profile avatar ────────────────────────────────────────────────────────────

class _ProfileAvatar extends ConsumerWidget {
  final VoidCallback onTap;

  const _ProfileAvatar({required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(profileProvider);

    final initials = profileAsync.when(
      data: (p) => p.initials,
      loading: () => '',
      error: (e, st) => '',
    );

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1A73E8), Color(0xFF0D47A1)],
          ),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.primaryLight, width: 1.5),
        ),
        child: initials.isNotEmpty
            ? Center(
                child: Text(
                  initials,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              )
            : const Icon(Icons.person_rounded, color: Colors.white, size: 20),
      ),
    );
  }
}
