import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/models/landing_page_section.dart';
import '../../domain/models/section_type.dart';

class SectionListTile extends StatefulWidget {
  const SectionListTile({
    super.key,
    required this.section,
    required this.index,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleEnabled,
  });

  final LandingPageSection section;
  final int index;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<bool> onToggleEnabled;

  @override
  State<SectionListTile> createState() => _SectionListTileState();
}

class _SectionListTileState extends State<SectionListTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final sectionType = SectionType.fromDbKey(widget.section.sectionType);
    final typeLabel = sectionType?.displayName ?? widget.section.sectionType;
    final typeIcon = sectionType?.icon ?? Icons.widgets_rounded;
    final isCanonical = sectionType?.isCanonical ?? false;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: _hovered
              ? AppColors.background
              : AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: widget.section.isEnabled
                ? AppColors.border
                : AppColors.border.withValues(alpha: 0.5),
          ),
          boxShadow: _hovered
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : [],
        ),
        child: Row(
          children: [
            // ── Drag handle ───────────────────────────────────────────────
            // HitTestBehavior.opaque is required on Flutter Web: the default
            // deferToChild used by ReorderableDragStartListener can miss
            // onPointerDown when nested MouseRegion widgets shadow the hit
            // path through the CanvasKit pointer-routing layer.
            MouseRegion(
              cursor: SystemMouseCursors.grab,
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (PointerDownEvent event) {
                  SliverReorderableList.maybeOf(context)
                      ?.startItemDragReorder(
                    index: widget.index,
                    event: event,
                    recognizer: ImmediateMultiDragGestureRecognizer(
                        debugOwner: this),
                  );
                },
                child: const Padding(
                  padding: EdgeInsets.fromLTRB(0, 6, 12, 6),
                  child: Icon(
                    Icons.drag_indicator_rounded,
                    size: 20,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),

            // ── Order badge ───────────────────────────────────────────────
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: widget.section.isEnabled
                    ? AppColors.primary.withValues(alpha: 0.08)
                    : AppColors.border,
                borderRadius: BorderRadius.circular(6),
              ),
              alignment: Alignment.center,
              child: Text(
                '${widget.index + 1}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: widget.section.isEnabled
                      ? AppColors.primary
                      : AppColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: 12),

            // ── Type icon ─────────────────────────────────────────────────
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isCanonical
                    ? AppColors.accent.withValues(alpha: 0.1)
                    : AppColors.border.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                typeIcon,
                size: 18,
                color: isCanonical ? AppColors.accent : AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: 12),

            // ── Names ─────────────────────────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.section.sectionName,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: widget.section.isEnabled
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isCanonical
                              ? AppColors.accent.withValues(alpha: 0.08)
                              : AppColors.border,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          typeLabel,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: isCanonical
                                ? AppColors.accent
                                : AppColors.textSecondary,
                          ),
                        ),
                      ),
                      if (widget.section.isPublished) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.success.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'Published',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              color: AppColors.success,
                            ),
                          ),
                        ),
                      ] else ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.warning.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'Draft',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              color: AppColors.warning,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),

            // ── Enabled toggle ────────────────────────────────────────────
            Tooltip(
              message: widget.section.isEnabled ? 'Visible' : 'Hidden',
              child: Switch(
                value: widget.section.isEnabled,
                onChanged: widget.onToggleEnabled,
                activeThumbColor: AppColors.accent,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const SizedBox(width: 4),

            // ── Edit button ───────────────────────────────────────────────
            IconButton(
              onPressed: widget.onEdit,
              icon: const Icon(Icons.edit_outlined, size: 18),
              tooltip: 'Edit',
              color: AppColors.textSecondary,
              hoverColor: AppColors.accent.withValues(alpha: 0.1),
            ),

            // ── More menu ─────────────────────────────────────────────────
            PopupMenuButton<String>(
              icon: Icon(
                Icons.more_vert_rounded,
                size: 18,
                color: AppColors.textSecondary,
              ),
              onSelected: (value) {
                if (value == 'delete') widget.onDelete();
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline_rounded,
                          size: 16, color: AppColors.error),
                      SizedBox(width: 8),
                      Text('Delete', style: TextStyle(color: AppColors.error)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
