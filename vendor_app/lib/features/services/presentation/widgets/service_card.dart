import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/format_utils.dart';
import '../../domain/models/assigned_service.dart';

class ServiceCard extends StatefulWidget {
  const ServiceCard({
    super.key,
    required this.service,
    required this.onToggle,
  });

  final AssignedService service;
  final Future<void> Function(bool) onToggle;

  @override
  State<ServiceCard> createState() => _ServiceCardState();
}

class _ServiceCardState extends State<ServiceCard> {
  bool _toggling = false;

  Future<void> _handleToggle(bool value) async {
    if (_toggling) return;
    setState(() => _toggling = true);
    try {
      await widget.onToggle(value);
    } finally {
      if (mounted) setState(() => _toggling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.service;
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.serviceName,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (s.categoryName != null || s.subCategoryName != null) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 4,
                      children: [
                        if (s.categoryName != null)
                          _CategoryChip(label: s.categoryName!),
                        if (s.subCategoryName != null)
                          _CategoryChip(label: s.subCategoryName!, muted: true),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        FormatUtils.currency(s.basePrice),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                      if (s.customPrice != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          'Custom: ${FormatUtils.currency(s.customPrice!)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (_toggling)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              )
            else
              Switch(
                value: s.isActive,
                onChanged: _handleToggle,
              ),
          ],
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.label, this.muted = false});

  final String label;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: muted ? AppColors.background : AppColors.primaryLight,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: muted ? AppColors.textSecondary : AppColors.primary,
            ),
      ),
    );
  }
}
