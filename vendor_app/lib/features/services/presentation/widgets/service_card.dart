import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/format_utils.dart';
import '../../../../core/widgets/confirmation_dialog.dart';
import '../../domain/models/assigned_service.dart';

class ServiceCard extends StatefulWidget {
  const ServiceCard({
    super.key,
    required this.service,
    required this.onRemove,
  });

  final AssignedService service;
  final Future<void> Function() onRemove;

  @override
  State<ServiceCard> createState() => _ServiceCardState();
}

class _ServiceCardState extends State<ServiceCard> {
  bool _removing = false;

  Future<void> _handleRemove() async {
    if (_removing) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => ConfirmationDialog(
        title: 'Remove Service',
        message: 'Are you sure you want to remove '
            '"${widget.service.serviceName}" from your services?',
        confirmLabel: 'Remove',
        isDestructive: true,
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _removing = true);
    try {
      await widget.onRemove();
    } finally {
      if (mounted) setState(() => _removing = false);
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
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
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
                  Text(
                    FormatUtils.currency(s.basePrice),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            if (_removing)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded),
                color: AppColors.textHint,
                tooltip: 'Remove service',
                onPressed: _handleRemove,
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
