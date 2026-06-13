import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/format_utils.dart';
import '../../domain/models/catalog_service.dart';

class CatalogServiceTile extends StatelessWidget {
  const CatalogServiceTile({
    super.key,
    required this.service,
    required this.selected,
    required this.onTap,
    this.alreadyAssigned = false,
  });

  final CatalogService service;
  final bool selected;
  final VoidCallback onTap;
  final bool alreadyAssigned;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      onTap: alreadyAssigned ? null : onTap,
      leading: alreadyAssigned
          ? const Icon(Icons.check_circle_rounded, color: AppColors.success)
          : Checkbox(
              value: selected,
              onChanged: (_) => onTap(),
              activeColor: AppColors.primary,
            ),
      title: Text(
        service.name,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color:
              alreadyAssigned ? AppColors.textSecondary : AppColors.textPrimary,
        ),
      ),
      subtitle: Text(
        [service.categoryName, service.subCategoryName]
            .whereType<String>()
            .join(' › '),
        style: theme.textTheme.bodySmall?.copyWith(
          color: AppColors.textSecondary,
        ),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            FormatUtils.currency(service.basePrice),
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
          if (service.estimatedDuration != null)
            Text(
              '${service.estimatedDuration} min',
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppColors.textHint,
              ),
            ),
        ],
      ),
    );
  }
}
