import 'dart:ui';
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
/// correctly position the body below it.
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
  Size get preferredSize => const Size.fromHeight(84);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isWide = MediaQuery.sizeOf(context).width >= 768;

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
                    spreadRadius: 0,
                    offset: const Offset(0, 4),
                  ),
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
                height: 84,
                decoration: BoxDecoration(
                  color: Colors.white
                      .withAlpha(isScrolled ? 224 : 247),
                  border: Border(
                    bottom: BorderSide(
                      color: AppColors.divider
                          .withAlpha(isScrolled ? 127 : 255),
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
                      child: isWide
                          ? _WideRow(
                              onLogoTap: onLogoTap,
                              onProfileTap: onProfileTap,
                            )
                          : _MobileRow(
                              onLogoTap: onLogoTap,
                              onProfileTap: onProfileTap,
                            ),
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

        // Search bar
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 540),
              child: const _GlobalSearchBar(),
            ),
          ),
        ),
        const SizedBox(width: 20),

        // Action buttons
        _NotifButton(
          onTap: () => AppModalDialog.show(
            context: context,
            child: const NotificationsModal(),
          ),
        ),
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
        _NotifButton(
          onTap: () => AppModalDialog.show(
            context: context,
            child: const NotificationsModal(),
          ),
        ),
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
    final w = MediaQuery.sizeOf(context).width;
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

// ── Global search bar ─────────────────────────────────────────────────────────

class _GlobalSearchBar extends StatefulWidget {
  const _GlobalSearchBar();

  @override
  State<_GlobalSearchBar> createState() => _GlobalSearchBarState();
}

class _GlobalSearchBarState extends State<_GlobalSearchBar> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      setState(() => _focused = _focusNode.hasFocus);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    final query = _controller.text.trim();
    context.push('/search', extra: query.isEmpty ? null : query);
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      height: 44,
      decoration: BoxDecoration(
        color: _focused ? Colors.white : AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: _focused
              ? AppColors.gold.withAlpha(153)
              : AppColors.border,
          width: _focused ? 1.5 : 0.8,
        ),
        boxShadow: _focused
            ? [
                BoxShadow(
                  color: AppColors.gold.withAlpha(26),
                  blurRadius: 12,
                  spreadRadius: 0,
                ),
              ]
            : null,
      ),
      child: Row(
        children: [
          const SizedBox(width: 14),
          Icon(
            Icons.search_rounded,
            size: 18,
            color: _focused ? AppColors.gold : AppColors.textHint,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Theme(
              data: Theme.of(context).copyWith(
                splashColor: Colors.transparent,
                highlightColor: Colors.transparent,
                hoverColor: Colors.transparent,
              ),
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _submit(),
                style: tt.bodySmall?.copyWith(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                ),
                decoration: InputDecoration(
                  hintText: 'Search for services...',
                  hintStyle: tt.bodySmall?.copyWith(
                    color: AppColors.textHint,
                    fontSize: 14,
                  ),
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
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Icon(Icons.clear_rounded,
                          size: 16, color: AppColors.textHint),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Notification button ───────────────────────────────────────────────────────

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
    final unreadCount = ref.watch(unreadCountProvider);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: _hovered ? AppColors.goldLight : AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _hovered
                  ? AppColors.gold.withAlpha(100)
                  : AppColors.border,
              width: 0.8,
            ),
          ),
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              Icon(
                Icons.notifications_outlined,
                size: 20,
                color: _hovered ? AppColors.primary : AppColors.textPrimary,
              ),
              if (unreadCount > 0)
                Positioned(
                  top: 8,
                  right: 8,
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
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: _hovered ? AppColors.goldLight : AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _hovered
                  ? AppColors.gold.withAlpha(100)
                  : AppColors.border,
              width: 0.8,
            ),
          ),
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              Icon(
                Icons.shopping_cart_outlined,
                size: 20,
                color: _hovered ? AppColors.primary : AppColors.textPrimary,
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
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: _hovered ? AppColors.goldLight : AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _hovered
                  ? AppColors.gold.withAlpha(100)
                  : AppColors.border,
              width: 0.8,
            ),
          ),
          child: Icon(widget.icon, size: 20, color: AppColors.textPrimary),
        ),
      ),
    );
  }
}

// ── Profile avatar ────────────────────────────────────────────────────────────

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
    final initials = ref.watch(profileProvider).when(
          data: (p) => p.initials,
          loading: () => '',
          error: (e, st) => '',
        );

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.textPrimary,
            shape: BoxShape.circle,
            border: Border.all(
              color: _hovered ? AppColors.gold : AppColors.gold.withAlpha(80),
              width: _hovered ? 2.0 : 1.5,
            ),
            boxShadow: _hovered
                ? [
                    BoxShadow(
                      color: AppColors.gold.withAlpha(64),
                      blurRadius: 10,
                      spreadRadius: 0,
                    ),
                  ]
                : null,
          ),
          child: initials.isNotEmpty
              ? Center(
                  child: Text(
                    initials,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              : const Icon(
                  Icons.person_rounded,
                  color: Colors.white,
                  size: 20,
                ),
        ),
      ),
    );
  }
}
