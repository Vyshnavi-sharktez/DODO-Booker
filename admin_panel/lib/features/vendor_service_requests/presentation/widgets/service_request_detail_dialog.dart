import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../service_faqs/presentation/widgets/custom_service_faqs_dialog.dart';
import '../../application/providers/vendor_service_requests_providers.dart';
import '../../domain/models/vendor_service_request.dart';

class ServiceRequestDetailDialog extends ConsumerStatefulWidget {
  const ServiceRequestDetailDialog({super.key, required this.request});

  final VendorServiceRequest request;

  @override
  ConsumerState<ServiceRequestDetailDialog> createState() =>
      _ServiceRequestDetailDialogState();
}

class _ServiceRequestDetailDialogState
    extends ConsumerState<ServiceRequestDetailDialog> {
  bool _showRejectForm = false;
  bool _busy = false;
  final _reasonCtrl = TextEditingController();

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _serviceAccept() async {
    setState(() => _busy = true);
    try {
      await ref
          .read(vendorServiceRequestsNotifierProvider.notifier)
          .accept(widget.request.id);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _serviceReject() async {
    final reason = _reasonCtrl.text.trim();
    if (reason.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a rejection reason.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(vendorServiceRequestsNotifierProvider.notifier)
          .reject(widget.request.id, reason: reason);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.request;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header ──────────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 20),
              decoration: const BoxDecoration(
                color: AppColors.primary,
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  Icon(
                    widget.request.isDeleteService || widget.request.isPendingDeletion
                        ? Icons.delete_outline_rounded
                        : widget.request.isPriceChange
                            ? Icons.edit_outlined
                            : Icons.inbox_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.request.requestTypeLabel,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded,
                        color: Colors.white70),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),

            // ── Body ────────────────────────────────────────────────────────
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: _buildBody(r),
              ),
            ),

            // ── Footer ──────────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
              decoration: const BoxDecoration(
                border: Border(
                    top: BorderSide(color: AppColors.border)),
              ),
              child: _buildFooter(r),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(VendorServiceRequest r) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StatusBadge(status: r.status),
        const SizedBox(height: 20),

        const _SectionLabel('Vendor'),
        const SizedBox(height: 12),
        _DetailRow('Business', r.vendorName),
        if (r.vendorTier != null) _DetailRow('Tier', r.vendorTier!),
        _DetailRow('Submitted', r.formattedDate),
        const SizedBox(height: 20),

        const _SectionLabel('Service Details'),
        const SizedBox(height: 12),
        _DetailRow('Service Name', r.serviceName),

        if (r.isPriceChange) ...[
          _DetailRow('Current Price', r.formattedPrice),
          _DetailRow('Requested Price', r.formattedNewPrice),
        ] else if (r.isDeleteService || r.isPendingDeletion) ...[
          _DetailRow('Current Price', r.formattedPrice),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
            ),
            child: const Text(
              'The vendor is requesting permanent removal of this service.',
              style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
            ),
          ),
        ] else ...[
          if (r.description != null && r.description!.isNotEmpty)
            _DetailRow('Description', r.description!),
          _DetailRow('Price', r.formattedPrice),
          if (r.imageUrl != null) ...[
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                r.imageUrl!,
                height: 160,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  height: 80,
                  color: AppColors.border,
                  child: const Center(
                    child: Icon(Icons.broken_image_outlined,
                        color: AppColors.textSecondary),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          const _SectionLabel('Warranty'),
          const SizedBox(height: 12),
          _DetailRow('Coverage', r.warrantyEnabled ? 'Enabled' : 'Disabled'),
          if (r.warrantyEnabled) ...[
            if (r.warrantyDays != null)
              _DetailRow('Duration', '${r.warrantyDays} days'),
            if (r.warrantyCovers != null && r.warrantyCovers!.isNotEmpty) ...[
              const SizedBox(height: 8),
              _MultiLineDetail(label: 'Covers', text: r.warrantyCovers!),
            ],
            if (r.warrantyExclusions != null && r.warrantyExclusions!.isNotEmpty) ...[
              const SizedBox(height: 8),
              _MultiLineDetail(label: 'Does Not Cover', text: r.warrantyExclusions!),
            ],
          ],
        ],

        if (r.isRejected &&
            r.rejectionReason != null &&
            r.rejectionReason!.isNotEmpty) ...[
          const SizedBox(height: 20),
          const _SectionLabel('Rejection Reason'),
          const SizedBox(height: 8),
          _ReasonBox(reason: r.rejectionReason!),
        ],

        if (_showRejectForm) ...[
          const SizedBox(height: 20),
          const _SectionLabel('Rejection Reason *'),
          const SizedBox(height: 8),
          TextFormField(
            controller: _reasonCtrl,
            maxLines: 3,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Explain why this request is being rejected…',
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildFooter(VendorServiceRequest r) {
    if (r.isCompleted || r.isRejected || r.isDeleted || r.isNeedsCatalog) {
      return _closeOnly();
    }

    if (_showRejectForm) {
      return Row(
        children: [
          TextButton(
            onPressed:
                _busy ? null : () => setState(() => _showRejectForm = false),
            child: const Text('Back'),
          ),
          const Spacer(),
          OutlinedButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          const SizedBox(width: 10),
          FilledButton(
            onPressed: _busy ? null : _serviceReject,
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Confirm Rejection'),
          ),
        ],
      );
    }

    final isDeletion = r.isDeleteService || r.isPendingDeletion;
    final acceptLabel = isDeletion ? 'Approve Deletion' : 'Accept';

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        OutlinedButton(
          onPressed:
              _busy ? null : () => setState(() => _showRejectForm = true),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.error,
            side: BorderSide(color: AppColors.error.withValues(alpha: 0.6)),
          ),
          child: const Text('Reject'),
        ),
        const SizedBox(width: 12),
        FilledButton(
          onPressed: _busy ? null : _serviceAccept,
          style: FilledButton.styleFrom(
            backgroundColor: isDeletion ? AppColors.error : AppColors.primary,
          ),
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : Text(acceptLabel),
        ),
      ],
    );
  }

  Widget _closeOnly() {
    final r = widget.request;
    final showQA = r.isCompleted && r.isNewService;
    return Row(
      mainAxisAlignment:
          showQA ? MainAxisAlignment.spaceBetween : MainAxisAlignment.end,
      children: [
        if (showQA)
          OutlinedButton.icon(
            onPressed: () => CustomServiceFaqsDialog.show(
              context,
              customServiceId: r.id,
              serviceName: r.serviceName,
              showQuestions: true,
            ),
            icon: const Icon(Icons.help_outline_rounded, size: 16),
            label: const Text('Customer Q&A'),
          ),
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: const TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        color: AppColors.textSecondary,
        letterSpacing: 0.8,
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textSecondary),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReasonBox extends StatelessWidget {
  const _ReasonBox({required this.reason});
  final String reason;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border:
            Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Text(
        reason,
        style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
      ),
    );
  }
}

class _MultiLineDetail extends StatelessWidget {
  const _MultiLineDetail({required this.label, required this.text});
  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    final lines = text.split('\n').where((l) => l.trim().isNotEmpty).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 6),
        ...lines.map(
          (l) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('• ',
                    style: TextStyle(
                        fontSize: 13, color: AppColors.textSecondary)),
                Expanded(
                  child: Text(l.trim(),
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.textPrimary)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'needs_catalog' => ('Needs Catalog', AppColors.primary),
      'completed' => ('Completed', AppColors.success),
      'rejected' => ('Rejected', AppColors.error),
      'pending_deletion' => ('Pending Deletion', const Color(0xFFF59E0B)),
      'deleted' => ('Deleted', AppColors.error),
      _ => ('Pending Review', const Color(0xFFF59E0B)),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
