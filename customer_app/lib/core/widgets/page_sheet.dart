import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants/app_colors.dart';

/// Large desktop modal for presenting full-page content (Addresses, Wishlist, etc.)
/// on wide screens. On mobile, callers fall back to a normal push route.
///
/// Usage:
///   PageSheet.show(context, title: 'My Addresses', child: AddressScreen(inModal: true));
///   PageSheet.show(context, title: 'Book Now', isDark: true, child: BookingFlowModal(...));
class PageSheet extends StatelessWidget {
  final String title;
  final Widget child;
  final bool isDark;

  const PageSheet({
    super.key,
    required this.title,
    required this.child,
    this.isDark = false,
  });

  static Future<T?> show<T>(
    BuildContext context, {
    required String title,
    required Widget child,
    bool isDark = false,
  }) {
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: false,
      barrierLabel: '',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (ctx, anim1, anim2) =>
          PageSheet(title: title, isDark: isDark, child: child),
      transitionBuilder: (ctx, anim, secAnim, child) => FadeTransition(
        opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.95, end: 1.0).animate(
            CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
          ),
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    // Fixed dimensions shared by every dialog — never grow or shrink with content.
    final modalW = (size.width * 0.9).clamp(320.0, 900.0);
    final modalH = size.height * 0.82;

    final cardColor = isDark ? const Color(0xFF0F0F0F) : AppColors.surface;

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          Navigator.of(context).maybePop();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Stack(
        children: [
          // Blurred dim backdrop — uses maybePop so PopScope inside child can block dismiss.
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.of(context).maybePop(),
              behavior: HitTestBehavior.opaque,
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                child: const ColoredBox(color: Color(0x70000000)),
              ),
            ),
          ),

          // Modal card
          Center(
            child: SizedBox(
              width: modalW,
              height: modalH,
              child: Material(
                color: cardColor,
                borderRadius: BorderRadius.circular(24),
                clipBehavior: Clip.antiAlias,
                elevation: 24,
                shadowColor: Colors.black38,
                child: Column(
                  children: [
                    _SheetHeader(title: title, isDark: isDark),
                    Expanded(
                      child: MediaQuery.removePadding(
                        context: context,
                        removeTop: true,
                        child: child,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetHeader extends StatelessWidget {
  final String title;
  final bool isDark;
  const _SheetHeader({required this.title, this.isDark = false});

  @override
  Widget build(BuildContext context) {
    final headerBg = isDark ? const Color(0xFF0A0A0A) : AppColors.surface;
    final borderColor = isDark ? const Color(0xFF252525) : AppColors.divider;
    final textColor = isDark ? Colors.white : null;
    final iconColor = isDark ? Colors.white70 : AppColors.textSecondary;

    return Container(
      height: 60,
      decoration: BoxDecoration(
        color: headerBg,
        border: Border(bottom: BorderSide(color: borderColor, width: 0.8)),
      ),
      padding: const EdgeInsets.only(left: 24, right: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: textColor,
                  ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 20),
            onPressed: () => Navigator.of(context).maybePop(),
            style: IconButton.styleFrom(foregroundColor: iconColor),
          ),
        ],
      ),
    );
  }
}
