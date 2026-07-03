import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../service_addons/application/providers/service_addons_providers.dart';
import '../../../service_addons/domain/models/service_addon.dart';
import '../../../services/domain/models/service.dart';
import 'catalog_callbacks.dart';

/// Renders a single service row with inline active-addon chips below it.
/// Chips refresh automatically when [serviceAddonsByServiceIdProvider] is
/// invalidated (e.g. after the Manage Add-ons dialog closes).
class ServiceTile extends ConsumerWidget {
  const ServiceTile({
    super.key,
    required this.service,
    required this.callbacks,
  });

  final Service service;
  final CatalogCallbacks callbacks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final addonsAsync =
        ref.watch(serviceAddonsByServiceIdProvider(service.id));
    final activeAddons = addonsAsync.valueOrNull
            ?.where((a) => a.isActive)
            .toList() ??
        [];

    return Padding(
      padding: const EdgeInsets.only(left: 64, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Service row ────────────────────────────────────────────────────
          Container(
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
                    onChanged: (val) =>
                        callbacks.onToggleServiceActive(service, val),
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
                  IconButton(
                    icon: const Icon(Icons.extension_rounded, size: 16),
                    tooltip: 'Manage Add-ons',
                    color: AppColors.primary,
                    onPressed: () => callbacks.onManageAddons(service),
                  ),
                ],
              ),
            ),
          ),

          // ── Active add-on chips ────────────────────────────────────────────
          if (activeAddons.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 5, 4, 0),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children:
                    activeAddons.map((a) => _AddonChip(addon: a)).toList(),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Badge ──────────────────────────────────────────────────────────────────────

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

// ── Add-on chip ────────────────────────────────────────────────────────────────

class _AddonChip extends StatelessWidget {
  const _AddonChip({required this.addon});
  final ServiceAddon addon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(6),
        border:
            Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.extension_rounded,
              size: 10, color: AppColors.primary),
          const SizedBox(width: 4),
          Text(
            addon.name,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            '₹${addon.price.toInt()}',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}
