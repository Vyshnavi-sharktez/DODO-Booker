import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../services/domain/models/service.dart';
import '../../../sub_categories/domain/models/sub_category.dart';
import 'catalog_callbacks.dart';
import 'service_tile.dart';

/// Renders one sub-category row and — when [isExpanded] — the [services] it
/// received. Only iterates over [services]; never reads from a provider or
/// filters globally.
class SubCategoryTile extends StatelessWidget {
  const SubCategoryTile({
    super.key,
    required this.subCategory,
    required this.services,
    required this.isExpanded,
    required this.onToggle,
    required this.callbacks,
  });

  final SubCategory subCategory;

  /// Already pre-filtered to belong exclusively to [subCategory].
  final List<Service> services;

  final bool isExpanded;
  final VoidCallback onToggle;
  final CatalogCallbacks callbacks;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(),
          if (isExpanded) ...[
            for (final svc in services)
              ServiceTile(service: svc, callbacks: callbacks),
            _addServiceButton(),
          ],
        ],
      ),
    );
  }

  Widget _header() {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F4FF),
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
                  size: 18,
                  color: services.isEmpty
                      ? Colors.transparent
                      : AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.folder_open_rounded,
                size: 18,
                color: AppColors.primaryLight,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  subCategory.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 13.5,
                    color: AppColors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
              if (services.isNotEmpty) ...[
                _CountChip(
                  label: '${services.length} svc',
                  color: AppColors.accent,
                ),
                const SizedBox(width: 6),
              ],
              Switch(
                value: subCategory.isActive,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: (val) =>
                    callbacks.onToggleSubCategoryActive(subCategory, val),
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 17),
                tooltip: 'Edit',
                color: AppColors.textSecondary,
                onPressed: () => callbacks.onEditSubCategory(subCategory),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 17),
                tooltip: 'Delete',
                color: AppColors.error,
                onPressed: () => callbacks.onDeleteSubCategory(subCategory),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline, size: 17),
                tooltip: 'Add Service',
                color: AppColors.accent,
                onPressed: () => callbacks.onAddService(subCategory),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _addServiceButton() {
    return Padding(
      padding: const EdgeInsets.only(left: 40, bottom: 6),
      child: TextButton.icon(
        onPressed: () => callbacks.onAddService(subCategory),
        icon: const Icon(Icons.add, size: 13),
        label: const Text('Add Service', style: TextStyle(fontSize: 12)),
        style: TextButton.styleFrom(
          foregroundColor: AppColors.accent,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
