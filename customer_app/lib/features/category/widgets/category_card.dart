import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/icon_registry.dart';
import '../../../core/utils/service_image_registry.dart';
import '../../../models/category_model.dart';

class CategoryCard extends StatefulWidget {
  final CategoryModel category;
  final int colorIndex;
  final VoidCallback onTap;

  const CategoryCard({
    super.key,
    required this.category,
    required this.colorIndex,
    required this.onTap,
  });

  @override
  State<CategoryCard> createState() => _CategoryCardState();
}

class _CategoryCardState extends State<CategoryCard> {
  bool _hovered = false;

  static const _bgColors = [
    Color(0xFFE3F2FD), Color(0xFFFFF3E0), Color(0xFFE8F5E9),
    Color(0xFFFCE4EC), Color(0xFFEDE7F6), Color(0xFFE0F7FA),
    Color(0xFFFFF8E1), Color(0xFFF3E5F5),
  ];
  static const _iconColors = [
    Color(0xFF1565C0), Color(0xFFE65100), Color(0xFF2E7D32),
    Color(0xFFC62828), Color(0xFF4527A0), Color(0xFF00838F),
    Color(0xFFF57F17), Color(0xFF6A1B9A),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cat = widget.category;
    final idx = widget.colorIndex % _bgColors.length;
    final imageUrl = ServiceImageRegistry.resolve(cat.imageUrl, cat.name);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _hovered
                  ? _iconColors[idx].withAlpha(70)
                  : cs.outline.withAlpha(80),
              width: _hovered ? 1.3 : 0.8,
            ),
            boxShadow: [
              BoxShadow(
                color: _hovered
                    ? _iconColors[idx].withAlpha(26)
                    : const Color(0x0A000000),
                blurRadius: _hovered ? 22 : 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(19),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Image area (58%) ────────────────────────────────────
                Expanded(
                  flex: 58,
                  child: AnimatedScale(
                    scale: _hovered ? 1.04 : 1.0,
                    duration: const Duration(milliseconds: 160),
                    child: Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                      loadingBuilder: (_, child, progress) {
                        if (progress == null) return child;
                        return Container(color: _bgColors[idx]);
                      },
                      errorBuilder: (_, e, s) => Container(
                        color: _bgColors[idx],
                        child: Center(
                          child: Icon(
                            IconRegistry.resolve(cat.iconKey, cat.name),
                            size: 44,
                            color: _iconColors[idx],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // ── Info area (42%) ─────────────────────────────────────
                Expanded(
                  flex: 42,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          cat.name,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: _hovered
                                ? _iconColors[idx]
                                : cs.onSurface,
                            height: 1.25,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const Spacer(),
                        if (cat.serviceCount > 0)
                          Text(
                            '${cat.serviceCount} services',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: _hovered
                                  ? _iconColors[idx].withAlpha(180)
                                  : cs.onSurface.withAlpha(120),
                            ),
                          ),
                      ],
                    ),
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
