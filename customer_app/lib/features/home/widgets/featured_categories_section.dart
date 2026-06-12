import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/section_header.dart';
import '../../../models/category_model.dart';

class FeaturedCategoriesSection extends StatelessWidget {
  final AsyncValue<List<CategoryModel>> asyncCategories;

  const FeaturedCategoriesSection({super.key, required this.asyncCategories});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SectionHeader(
            title: 'Categories',
            onSeeAll: () {
              // TODO: navigate to all categories
            },
          ),
        ),
        const SizedBox(height: 14),
        asyncCategories.when(
          loading: () => const _CategoriesSkeleton(),
          error: (_, _) => const _CategoriesError(),
          data: (categories) {
            if (categories.isEmpty) return const _CategoriesEmpty();
            return _CategoriesGrid(categories: categories);
          },
        ),
      ],
    );
  }
}

// ── Responsive grid ───────────────────────────────────────────────────────────

class _CategoriesGrid extends StatelessWidget {
  final List<CategoryModel> categories;
  const _CategoriesGrid({required this.categories});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 500 ? 6 : 4;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              childAspectRatio: 0.82,
              crossAxisSpacing: 4,
              mainAxisSpacing: 10,
            ),
            itemCount: categories.length,
            itemBuilder: (context, index) => _CategoryCard(
              category: categories[index],
              colorIndex: index,
            ),
          ),
        );
      },
    );
  }
}

// ── Category card ─────────────────────────────────────────────────────────────

class _CategoryCard extends StatelessWidget {
  final CategoryModel category;
  final int colorIndex;

  const _CategoryCard({required this.category, required this.colorIndex});

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

  IconData _resolveIcon(String name) {
    final n = name.toLowerCase();
    if (n.contains('clean')) return Icons.cleaning_services;
    if (n.contains('plumb')) return Icons.plumbing;
    if (n.contains('electr')) return Icons.electrical_services;
    if (n.contains('paint')) return Icons.format_paint;
    if (n.contains('carpen')) return Icons.build;
    if (n.contains('pest')) return Icons.bug_report;
    if (n.contains('appli')) return Icons.kitchen;
    if (n.contains('shift') || n.contains('moving')) return Icons.local_shipping;
    if (n.contains('salon') || n.contains('beauty')) return Icons.content_cut;
    if (n.contains('garden')) return Icons.yard;
    return Icons.home_repair_service;
  }

  @override
  Widget build(BuildContext context) {
    final idx = colorIndex % _bgColors.length;

    return GestureDetector(
      onTap: () {
        // TODO: navigate to category
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: _bgColors[idx],
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(_resolveIcon(category.name), color: _iconColors[idx], size: 28),
          ),
          const SizedBox(height: 6),
          Text(
            category.name,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ── Loading / Error / Empty states ────────────────────────────────────────────

class _CategoriesSkeleton extends StatelessWidget {
  const _CategoriesSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          childAspectRatio: 0.82,
          crossAxisSpacing: 4,
          mainAxisSpacing: 10,
        ),
        itemCount: 8,
        itemBuilder: (_, _) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.shimmerBase,
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            const SizedBox(height: 6),
            Container(
              height: 10,
              width: 40,
              decoration: BoxDecoration(
                color: AppColors.shimmerBase,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoriesError extends StatelessWidget {
  const _CategoriesError();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: AppColors.textHint, size: 32),
            SizedBox(height: 8),
            Text(
              'Could not load categories',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
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
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Text(
          'No categories available',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
      ),
    );
  }
}
