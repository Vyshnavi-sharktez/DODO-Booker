import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_colors.dart';
import '../../domain/models/vendor_document.dart';

class DocumentTile extends StatelessWidget {
  const DocumentTile({
    super.key,
    required this.document,
    required this.docType,
    required this.isReplacing,
    required this.onReplace,
    required this.onView,
  });

  final VendorDocument document;
  final DocumentTypeModel? docType;
  final bool isReplacing;
  final VoidCallback onReplace;
  final VoidCallback onView;

  @override
  Widget build(BuildContext context) {
    final isOther = document.documentType == 'other';
    final label = isOther && (document.customDocumentName?.isNotEmpty ?? false)
        ? document.customDocumentName!
        : (docType?.label ?? document.documentType);
    final icon = docType?.icon ?? Icons.description_outlined;

    final dateStr = document.createdAt != null
        ? DateFormat('d MMM yyyy').format(document.createdAt!)
        : null;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isReplacing)
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
              child: const LinearProgressIndicator(minHeight: 3),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: AppColors.primary, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      if (dateStr != null)
                        Text(
                          'Uploaded $dateStr',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _StatusBadge(status: document.verificationStatus),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: isReplacing ? null : onView,
                  style: TextButton.styleFrom(
                    minimumSize: Size.zero,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: const Icon(Icons.visibility_outlined, size: 16),
                  label: const Text('View'),
                ),
                const SizedBox(width: 4),
                FilledButton.tonalIcon(
                  onPressed: isReplacing ? null : onReplace,
                  style: FilledButton.styleFrom(
                    minimumSize: Size.zero,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Replace'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, color, bg) = switch (status) {
      'approved' => (
          'Verified',
          AppColors.success,
          const Color(0x2034A853),
        ),
      'rejected' => (
          'Rejected',
          AppColors.error,
          const Color(0x20EA4335),
        ),
      _ => (
          'Pending',
          AppColors.warning,
          const Color(0x20FBBC04),
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
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
