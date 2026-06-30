import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../constants/app_colors.dart';
import 'app_modal_dialog.dart';
import '../../features/notifications/widgets/notifications_modal.dart';
import '../../features/notifications/services/notification_providers.dart';
import '../../features/profile/services/profile_providers.dart';
import '../../features/cart/providers/cart_provider.dart';
import '../../features/cart/utils/cart_launcher.dart';

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

  // 84px gives the 76px desktop logo 4px breathing room on each side.
  // Tablet (60px) and mobile (50px) logos are comfortably centered in this space.
  @override
  Size get preferredSize => const Size.fromHeight(84);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isWide = MediaQuery.of(context).size.width >= 768;

    return Material(
      color: AppColors.surface,
      elevation: 0,
      child: SafeArea(
        bottom: false,
        child: Container(
          height: 84,
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(
              bottom: BorderSide(color: AppColors.divider, width: 0.8),
            ),
          ),
          child: Align(
            alignment: Alignment.center,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1440),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: isWide
                    ? _WideRow(onLogoTap: onLogoTap, onProfileTap: onProfileTap)
                    : _MobileRow(onLogoTap: onLogoTap, onProfileTap: onProfileTap),
              ),
            ),
          ),
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
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: onLogoTap,
            behavior: HitTestBehavior.opaque,
            child: const _DodoBrand(),
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: const _GlobalSearchBar(),
            ),
          ),
        ),
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
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: onLogoTap,
            behavior: HitTestBehavior.opaque,
            child: const _DodoBrand(),
          ),
        ),
        const Spacer(),
        _HeaderIconBtn(
          icon: Icons.search_rounded,
          onTap: () => context.push('/search'),
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
    final w = MediaQuery.of(context).size.width;
    // Desktop ≥1024 → 72px | Tablet 768–1024 → 62px | Mobile <768 → 50px
    final logoHeight = w >= 1024 ? 72.0 : w >= 768 ? 62.0 : 50.0;

    return Image.asset(
      'assets/images/logo.png',
      height: logoHeight,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      errorBuilder: (context, error, stack) => const _FallbackBrand(),
    );
  }
}

// Shown only if the asset fails to load (e.g. missing during development).
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
          child: const Icon(
            Icons.home_repair_service_rounded,
            color: AppColors.gold,
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
                  color: AppColors.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
              TextSpan(
                text: ' BOOKER',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w500,
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

class _GlobalSearchBar extends StatefulWidget {
  const _GlobalSearchBar();

  @override
  State<_GlobalSearchBar> createState() => _GlobalSearchBarState();
}

class _GlobalSearchBarState extends State<_GlobalSearchBar> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final query = _controller.text.trim();
    context.push('/search', extra: query.isEmpty ? null : query);
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Container(
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
          Expanded(
            child: Theme(
              data: Theme.of(context).copyWith(
                splashColor: Colors.transparent,
                highlightColor: Colors.transparent,
                hoverColor: Colors.transparent,
              ),
              child: TextField(
                controller: _controller,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _submit(),
                style: tt.bodySmall?.copyWith(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Search for services...',
                  hintStyle: tt.bodySmall?.copyWith(color: AppColors.textHint),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  focusedErrorBorder: InputBorder.none,
                  filled: false,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _controller,
            builder: (_, val, child) => val.text.isEmpty
                ? const SizedBox.shrink()
                : InkWell(
                    mouseCursor: SystemMouseCursors.click,
                    onTap: _controller.clear,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10),
                      child: Icon(Icons.clear_rounded,
                          size: 15, color: AppColors.textHint),
                    ),
                  ),
          ),
        ],
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

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
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

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          ScaffoldMessenger.of(context).clearSnackBars();
          openCart(context);
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
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
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

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AppColors.textPrimary,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: AppColors.gold.withAlpha(80), width: 1.5),
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
      ),
    );
  }
}
