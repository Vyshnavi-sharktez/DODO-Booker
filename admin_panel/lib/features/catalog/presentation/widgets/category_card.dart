import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../categories/domain/models/category.dart';
import '../../../services/domain/models/service.dart';
import '../../../sub_categories/domain/models/sub_category.dart';
import 'catalog_callbacks.dart';
import 'sub_category_tile.dart';

/// Renders one category row and — when [isExpanded] — its [subCategories].
/// For each sub-category it passes [servicesBySubId][sub.id] (an O(1) lookup)
/// to [SubCategoryTile]. No list is ever filtered inside this widget.
class CategoryCard extends StatelessWidget {
  const CategoryCard({
    super.key,
    required this.category,
    required this.subCategories,
    required this.servicesBySubId,
    required this.isExpanded,
    required this.onToggle,
    required this.isSubExpanded,
    required this.onToggleSub,
    required this.callbacks,
  });

  final Category category;

  /// Pre-filtered to belong exclusively to [category].
  final List<SubCategory> subCategories;

  /// Keyed by sub-category id. CategoryCard does a single key-lookup per sub
  /// to hand the correct list to SubCategoryTile.
  final Map<String, List<Service>> servicesBySubId;

  final bool isExpanded;
  final VoidCallback onToggle;

  final bool Function(String subId) isSubExpanded;
  final void Function(SubCategory) onToggleSub;

  final CatalogCallbacks callbacks;

  int get _totalServices => subCategories.fold(
        0,
        (sum, sub) => sum + (servicesBySubId[sub.id] ?? []).length,
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(),
        if (isExpanded) ...[
          for (final sub in subCategories)
            SubCategoryTile(
              key: ValueKey(sub.id),
              subCategory: sub,
              services: servicesBySubId[sub.id] ?? [],
              isExpanded: isSubExpanded(sub.id),
              onToggle: () => onToggleSub(sub),
              callbacks: callbacks,
            ),
          _addSubCategoryButton(),
        ],
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _header() {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              AnimatedRotation(
                turns: isExpanded ? 0.25 : 0,
                duration: const Duration(milliseconds: 150),
                child: Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: subCategories.isEmpty
                      ? Colors.transparent
                      : AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.folder_rounded,
                size: 20,
                color: AppColors.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  category.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: AppColors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
              if (subCategories.isNotEmpty) ...[
                _CountChip(
                  label: '${subCategories.length} sub',
                  color: AppColors.primary,
                ),
                const SizedBox(width: 6),
              ],
              if (_totalServices > 0) ...[
                _CountChip(
                  label: '$_totalServices svc',
                  color: AppColors.accent,
                ),
                const SizedBox(width: 6),
              ],
              Switch(
                value: category.isActive,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: (val) =>
                    callbacks.onToggleCategoryActive(category, val),
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 18),
                tooltip: 'Edit',
                color: AppColors.textSecondary,
                onPressed: () => callbacks.onEditCategory(category),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18),
                tooltip: 'Delete',
                color: AppColors.error,
                onPressed: () => callbacks.onDeleteCategory(category),
              ),
              IconButton(
                icon: const Icon(Icons.create_new_folder_outlined, size: 18),
                tooltip: 'Add Sub Category',
                color: AppColors.accent,
                onPressed: () => callbacks.onAddSubCategory(category),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _addSubCategoryButton() {
    return Padding(
      padding: const EdgeInsets.only(left: 40, bottom: 6),
      child: TextButton.icon(
        onPressed: () => callbacks.onAddSubCategory(category),
        icon: const Icon(Icons.add, size: 14),
        label: const Text('Add Sub Category', style: TextStyle(fontSize: 13)),
        style: TextButton.styleFrom(
          foregroundColor: AppColors.accent,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        ),
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
