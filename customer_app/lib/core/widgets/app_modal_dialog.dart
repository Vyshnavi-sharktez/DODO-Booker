import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import '../constants/app_colors.dart';

/// Reusable centered modal with blurred background.
/// Use [AppModalDialog.show] to display any child inside the modal container.
class AppModalDialog extends StatelessWidget {
  final String? title;
  final Widget? subtitle;
  final Widget child;
  final bool showClose;
  final bool barrierDismissible;
  final bool scrollable;
  final EdgeInsets contentPadding;
  final double maxWidth;

  const AppModalDialog({
    super.key,
    this.title,
    this.subtitle,
    required this.child,
    this.showClose = true,
    this.barrierDismissible = true,
    this.scrollable = true,
    this.contentPadding = const EdgeInsets.fromLTRB(24, 8, 24, 24),
    this.maxWidth = 480,
  });

  static Future<T?> show<T>({
    required BuildContext context,
    required Widget child,
    bool barrierDismissible = true,
  }) {
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: false,
      barrierLabel: '',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (ctx, anim1, anim2) => child,
      transitionBuilder: (ctx, anim, secAnim, child) => FadeTransition(
        opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.94, end: 1.0).animate(
            CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
          ),
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Blurred dark overlay
        Positioned.fill(
          child: GestureDetector(
            onTap: barrierDismissible ? () => Navigator.of(context).pop() : null,
            behavior: HitTestBehavior.opaque,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
              child: const ColoredBox(color: Color(0x70000000)),
            ),
          ),
        ),
        // Modal card — capped at 88 % of screen height so tall content scrolls
        // instead of growing off-screen.
        SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: maxWidth,
                maxHeight: MediaQuery.of(context).size.height * 0.88,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(55),
                          blurRadius: 48,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _ModalHeader(
                          title: title,
                          subtitle: subtitle,
                          showClose: showClose,
                        ),
                        Flexible(
                          child: scrollable
                              ? ScrollConfiguration(
                                  behavior: ScrollConfiguration.of(context)
                                      .copyWith(
                                    dragDevices: {
                                      PointerDeviceKind.touch,
                                      PointerDeviceKind.mouse,
                                      PointerDeviceKind.trackpad,
                                      PointerDeviceKind.stylus,
                                    },
                                  ),
                                  child: Scrollbar(
                                    thumbVisibility: true,
                                    child: SingleChildScrollView(
                                      padding: contentPadding,
                                      primary: true,
                                      child: child,
                                    ),
                                  ),
                                )
                              : Padding(
                                  padding: contentPadding,
                                  child: child,
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ModalHeader extends StatelessWidget {
  final String? title;
  final Widget? subtitle;
  final bool showClose;

  const _ModalHeader({this.title, this.subtitle, required this.showClose});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final hasContent = title != null || subtitle != null;

    if (!hasContent && !showClose) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 8, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (title != null) ...[
                      Text(
                        title!,
                        style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ],
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      DefaultTextStyle(
                        style: tt.bodySmall!.copyWith(color: AppColors.textSecondary),
                        child: subtitle!,
                      ),
                    ],
                  ],
                ),
              ),
              if (showClose)
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                  style: IconButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const Divider(height: 1),
      ],
    );
  }
}
