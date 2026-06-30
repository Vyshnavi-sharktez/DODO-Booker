import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../services/domain/models/service.dart';
import 'catalog_callbacks.dart';

/// Renders a single service row. Receives the [service] directly — does not
/// query any provider or filter any list.
class ServiceTile extends StatelessWidget {
  const ServiceTile({
    super.key,
    required this.service,
    required this.callbacks,
  });

  final Service service;
  final CatalogCallbacks callbacks;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 64, bottom: 4),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              const Icon(
                Icons.home_repair_service_rounded,
                size: 16,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  service.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                    color: AppColors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
              _Badge(
                '₹${service.basePrice.toStringAsFixed(0)}',
                const Color(0xFFEBF8F0),
                AppColors.success,
              ),
              const SizedBox(width: 6),
              _Badge(
                '${service.estimatedDuration}m',
                const Color(0xFFF0F4FF),
                AppColors.primary,
              ),
              const SizedBox(width: 4),
              Switch(
                value: service.isActive,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: (val) => callbacks.onToggleServiceActive(service, val),
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 16),
                tooltip: 'Edit',
                color: AppColors.textSecondary,
                onPressed: () => callbacks.onEditService(service),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 16),
                tooltip: 'Delete',
                color: AppColors.error,
                onPressed: () => callbacks.onDeleteService(service),
              ),
              IconButton(
                icon: const Icon(Icons.tune_rounded, size: 16),
                tooltip: 'Configure Attributes',
                color: AppColors.accent,
                onPressed: () => callbacks.onOpenAttributes(service),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.label, this.bgColor, this.fgColor);
  final String label;
  final Color bgColor;
  final Color fgColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: fgColor,
        ),
      ),
    );
  }
}
