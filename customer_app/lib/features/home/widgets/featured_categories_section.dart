import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/icon_registry.dart';
import '../../../core/widgets/section_header.dart';
import '../../../models/category_model.dart';

class FeaturedCategoriesSection extends StatelessWidget {
  final AsyncValue<List<CategoryModel>> asyncCategories;
  final ValueChanged<CategoryModel> onCategorySelected;

  const FeaturedCategoriesSection({
    super.key,
    required this.asyncCategories,
    required this.onCategorySelected,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: SectionHeader(title: 'Categories'),
        ),
        const SizedBox(height: 14),
        asyncCategories.when(
          loading: () => const _CategoriesSkeleton(),
          error: (_, _) => const _CategoriesError(),
          data: (categories) {
            if (categories.isEmpty) return const _CategoriesEmpty();
            return _CategoriesGrid(
              categories: categories,
              onCategorySelected: onCategorySelected,
            );
          },
        ),
      ],
    );
  }
}

// ── Responsive grid ───────────────────────────────────────────────────────────

class _CategoriesGrid extends StatelessWidget {
  final List<CategoryModel> categories;
  final ValueChanged<CategoryModel> onCategorySelected;

  const _CategoriesGrid({
    required this.categories,
    required this.onCategorySelected,
  });

  static int _crossAxisCount(double width) {
    if (width < 400) return 2;
    if (width < 600) return 3;
    if (width < 900) return 4;
    if (width < 1200) return 5;
    return 6;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = _crossAxisCount(constraints.maxWidth);
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            childAspectRatio: 0.85,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: categories.length,
          itemBuilder: (context, index) => _CategoryCard(
            category: categories[index],
            colorIndex: index,
            onTap: () => onCategorySelected(categories[index]),
          ),
        );
      },
    );
  }
}

// ── Category card ─────────────────────────────────────────────────────────────

class _CategoryCard extends StatefulWidget {
  final CategoryModel category;
  final int colorIndex;
  final VoidCallback onTap;

  const _CategoryCard({
    required this.category,
    required this.colorIndex,
    required this.onTap,
  });

  @override
  State<_CategoryCard> createState() => _CategoryCardState();
}

class _CategoryCardState extends State<_CategoryCard> {
  bool _hovered = false;

  static const _bgColors = [
    Color(0xFFE3F2FD),
    Color(0xFFFFF3E0),
    Color(0xFFE8F5E9),
    Color(0xFFFCE4EC),
    Color(0xFFEDE7F6),
    Color(0xFFE0F7FA),
    Color(0xFFFFF8E1),
    Color(0xFFF3E5F5),
  ];

  static const _iconColors = [
    Color(0xFF1565C0),
    Color(0xFFE65100),
    Color(0xFF2E7D32),
    Color(0xFFC62828),
    Color(0xFF4527A0),
    Color(0xFF00838F),
    Color(0xFFF57F17),
    Color(0xFF6A1B9A),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final idx = widget.colorIndex % _bgColors.length;
    final bg = _bgColors[idx];
    final iconColor = _iconColors[idx];

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _hovered
                  ? iconColor.withAlpha(90)
                  : cs.outline.withAlpha(80),
              width: _hovered ? 1.2 : 0.8,
            ),
            boxShadow: [
              BoxShadow(
                color: _hovered
                    ? iconColor.withAlpha(28)
                    : const Color(0x07000000),
                blurRadius: _hovered ? 16 : 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Icon area ──────────────────────────────────────────────
                Expanded(
                  flex: 3,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    color: _hovered ? bg : bg.withAlpha(200),
                    child: Center(
                      child: AnimatedScale(
                        scale: _hovered ? 1.12 : 1.0,
                        duration: const Duration(milliseconds: 150),
                        child: Icon(
                          IconRegistry.resolve(
                              widget.category.iconKey, widget.category.name),
                          size: 34,
                          color: iconColor,
                        ),
                      ),
                    ),
                  ),
                ),
                // ── Label area ─────────────────────────────────────────────
                Expanded(
                  flex: 2,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 6),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          widget.category.name,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _hovered
                                ? iconColor
                                : cs.onSurface,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (widget.category.serviceCount > 0) ...[
                          const SizedBox(height: 2),
                          Text(
                            '${widget.category.serviceCount} services',
                            style: TextStyle(
                              fontSize: 10,
                              color: cs.onSurface.withAlpha(120),
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
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

// ── Loading skeleton ──────────────────────────────────────────────────────────

class _CategoriesSkeleton extends StatelessWidget {
  const _CategoriesSkeleton();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          childAspectRatio: 0.85,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: 8,
        itemBuilder: (_, _) => Container(
          decoration: BoxDecoration(
            color: cs.onSurface.withAlpha(20),
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}

class _CategoriesError extends StatelessWidget {
  const _CategoriesError();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: cs.onSurface.withAlpha(120), size: 32),
            const SizedBox(height: 8),
            Text(
              'Could not load categories',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoriesEmpty extends StatelessWidget {
  const _CategoriesEmpty();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Text(
          'No categories available',
          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
        ),
      ),
    );
  }
}
