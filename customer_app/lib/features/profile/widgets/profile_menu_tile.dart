import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';

class ProfileMenuTile extends StatefulWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final String? badge;
  final VoidCallback? onTap;
  final bool isDestructive;

  const ProfileMenuTile({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    this.badge,
    this.onTap,
    this.isDestructive = false,
  });

  @override
  State<ProfileMenuTile> createState() => _ProfileMenuTileState();
}

class _ProfileMenuTileState extends State<ProfileMenuTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final effectiveIconColor =
        widget.isDestructive ? AppColors.error : widget.iconColor;
    final titleColor =
        widget.isDestructive ? AppColors.error : AppColors.textPrimary;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          color: _hovered
              ? (widget.isDestructive
                  ? AppColors.error.withAlpha(8)
                  : AppColors.primary.withAlpha(6))
              : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              // Icon badge
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: effectiveIconColor.withAlpha(16),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  widget.icon,
                  size: 20,
                  color: effectiveIconColor,
                ),
              ),

              const SizedBox(width: 14),

              // Title + subtitle
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.title,
                      style: tt.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: titleColor,
                      ),
                    ),
                    if (widget.subtitle != null) ...[
                      const SizedBox(height: 1),
                      Text(
                        widget.subtitle!,
                        style: tt.labelSmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // Badge
              if (widget.badge != null) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.error,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    widget.badge!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],

              // Trailing chevron
              if (!widget.isDestructive)
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: _hovered ? AppColors.textSecondary : AppColors.textHint,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Section wrapper ────────────────────────────────────────────────────────────

class ProfileMenuSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const ProfileMenuSection({
    super.key,
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
          child: Text(
            title.toUpperCase(),
            style: tt.labelSmall?.copyWith(
              color: AppColors.textHint,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
        ),
        // Outer container carries the shadow; ClipRRect inside clips ink effects
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0A000000),
                blurRadius: 10,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Container(
              color: AppColors.surface,
              child: Column(
                children: _withDividers(children),
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _withDividers(List<Widget> items) {
    final result = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      result.add(items[i]);
      if (i < items.length - 1) {
        result.add(
          const Divider(
            height: 1,
            indent: 70,
            endIndent: 16,
            color: AppColors.divider,
          ),
        );
      }
    }
    return result;
  }
}
