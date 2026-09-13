import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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

  List<Map<String, dynamic>>? _attrs; // null = loading, list = loaded

  // edit_service diff state
  VendorServiceRequest? _liveParent;
  bool _parentLoading = false;
  Set<String> _changedSections = {};
  int? _proposalAttrCount;
  int? _liveAttrCount;

  @override
  void initState() {
    super.initState();
    if (widget.request.isNewService) _loadAttrs();
    if (widget.request.isEditService) _loadParent();
  }

  Future<void> _loadAttrs() async {
    try {
      final data = await Supabase.instance.client
          .from('service_attributes')
          .select('name, service_attribute_options(option_name, price_adjustment)')
          .eq('custom_service_id', widget.request.id)
          .order('name', ascending: true);
      if (mounted) {
        setState(() => _attrs = List<Map<String, dynamic>>.from(data as List));
      }
    } catch (_) {
      if (mounted) setState(() => _attrs = []);
    }
  }

  Future<void> _loadParent() async {
    if (widget.request.parentRequestId == null) return;
    setState(() => _parentLoading = true);
    try {
      final parentId = widget.request.parentRequestId!;

      // Check already-loaded list first to avoid extra round-trip.
      var parent =
          (ref.read(vendorServiceRequestsNotifierProvider).valueOrNull ?? [])
              .where((r) => r.id == parentId)
              .firstOrNull;
      parent ??= await ref
          .read(vendorServiceRequestsRepositoryProvider)
          .fetchById(parentId);

      // Load attribute name-sets for both rows.
      final db = Supabase.instance.client;
      final proposalAttrs = await db
          .from('service_attributes')
          .select('name')
          .eq('custom_service_id', widget.request.id);
      final liveAttrs = await db
          .from('service_attributes')
          .select('name')
          .eq('custom_service_id', parentId);

      if (!mounted) return;

      final changed = <String>{};
      if (parent != null) {
        // Warranty diff.
        if (widget.request.warrantyEnabled != parent.warrantyEnabled ||
            widget.request.warrantyDays != parent.warrantyDays ||
            _norm(widget.request.warrantyCovers) != _norm(parent.warrantyCovers) ||
            _norm(widget.request.warrantyExclusions) !=
                _norm(parent.warrantyExclusions)) {
          changed.add('warranty');
        }
        // Content diff.
        if (!_strListEq(widget.request.includedItems, parent.includedItems) ||
            !_strListEq(widget.request.excludedItems, parent.excludedItems) ||
            widget.request.beforeAfterPairs.length !=
                parent.beforeAfterPairs.length) {
          changed.add('content');
        }
      }

      // Attrs diff by name-set.
      final pNames = (proposalAttrs as List)
          .map((a) => a['name'] as String? ?? '')
          .toSet();
      final lNames = (liveAttrs as List)
          .map((a) => a['name'] as String? ?? '')
          .toSet();
      if (pNames != lNames) changed.add('attrs');

      setState(() {
        _liveParent = parent;
        _changedSections = changed;
        _proposalAttrCount = pNames.length;
        _liveAttrCount = lNames.length;
        _parentLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _parentLoading = false);
    }
  }

  static String? _norm(String? s) =>
      (s == null || s.trim().isEmpty) ? null : s.trim();

  static bool _strListEq(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  // Dynamic title for edit_service proposals.
  String get _dialogTitle {
    if (!widget.request.isEditService) return widget.request.requestTypeLabel;
    if (_parentLoading || _liveParent == null) return 'Service Edit Pending Review';
    if (_changedSections.length == 1) {
      return switch (_changedSections.first) {
        'warranty' => 'Warranty Edit Pending Review',
        'content'  => 'Service Content Edit Pending Review',
        'attrs'    => 'Attributes / Variants Edit Pending Review',
        _          => 'Service Edit Pending Review',
      };
    }
    return 'Service Edit Pending Review';
  }

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
                    r.isEditService
                        ? Icons.edit_note_rounded
                        : r.isDeleteService || r.isPendingDeletion
                            ? Icons.delete_outline_rounded
                            : r.isPriceChange
                                ? Icons.edit_outlined
                                : Icons.inbox_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _dialogTitle,
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
                child: r.isEditService
                    ? _buildEditServiceBody(r)
                    : _buildBody(r),
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

  // ── edit_service body ──────────────────────────────────────────────────────

  Widget _buildEditServiceBody(VendorServiceRequest r) {
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

        const _SectionLabel('Service'),
        const SizedBox(height: 12),
        _DetailRow('Service Name', r.serviceName),
        const SizedBox(height: 20),

        if (_parentLoading)
          const Center(child: CircularProgressIndicator())
        else if (_liveParent != null && _changedSections.isEmpty)
          _buildNoChangesNote()
        else ...[
          if (_liveParent != null) ...[
            const _SectionLabel('Proposed Changes'),
            const SizedBox(height: 12),
          ],
          if (_changedSections.contains('warranty'))
            _buildWarrantyDiff(r, _liveParent!),
          if (_changedSections.contains('warranty') &&
              (_changedSections.contains('content') ||
                  _changedSections.contains('attrs')))
            const SizedBox(height: 12),
          if (_changedSections.contains('content'))
            _buildContentDiff(r, _liveParent!),
          if (_changedSections.contains('content') &&
              _changedSections.contains('attrs'))
            const SizedBox(height: 12),
          if (_changedSections.contains('attrs'))
            _buildAttrsDiff(),
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

  Widget _buildNoChangesNote() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline_rounded,
              size: 16, color: AppColors.textSecondary),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'No differences detected against the live service.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWarrantyDiff(
      VendorServiceRequest proposal, VendorServiceRequest live) {
    final rows = <Widget>[];

    if (proposal.warrantyEnabled != live.warrantyEnabled) {
      rows.add(_DiffRow(
        'Coverage',
        live.warrantyEnabled ? 'Enabled' : 'Disabled',
        proposal.warrantyEnabled ? 'Enabled' : 'Disabled',
      ));
    }
    if (proposal.warrantyDays != live.warrantyDays) {
      rows.add(_DiffRow(
        'Duration',
        live.warrantyDays != null ? '${live.warrantyDays} days' : '—',
        proposal.warrantyDays != null ? '${proposal.warrantyDays} days' : '—',
      ));
    }
    if (_norm(proposal.warrantyCovers) != _norm(live.warrantyCovers)) {
      rows.add(_DiffMultiLine(
        label: 'Covers',
        liveText: live.warrantyCovers,
        proposedText: proposal.warrantyCovers,
      ));
    }
    if (_norm(proposal.warrantyExclusions) != _norm(live.warrantyExclusions)) {
      rows.add(_DiffMultiLine(
        label: 'Does Not Cover',
        liveText: live.warrantyExclusions,
        proposedText: proposal.warrantyExclusions,
      ));
    }

    if (rows.isEmpty) return const SizedBox.shrink();
    return _ChangedSection(
      icon: Icons.shield_outlined,
      title: 'Warranty',
      children: rows,
    );
  }

  Widget _buildContentDiff(
      VendorServiceRequest proposal, VendorServiceRequest live) {
    final rows = <Widget>[];

    if (!_strListEq(proposal.includedItems, live.includedItems)) {
      rows.add(_DiffItemList(
        label: "What's Included",
        liveCount: live.includedItems.length,
        items: proposal.includedItems,
      ));
    }
    if (!_strListEq(proposal.excludedItems, live.excludedItems)) {
      rows.add(_DiffItemList(
        label: "What's Excluded",
        liveCount: live.excludedItems.length,
        items: proposal.excludedItems,
      ));
    }
    if (proposal.beforeAfterPairs.length != live.beforeAfterPairs.length) {
      rows.add(_DiffRow(
        'Before/After Pairs',
        '${live.beforeAfterPairs.length}',
        '${proposal.beforeAfterPairs.length}',
      ));
    }

    if (rows.isEmpty) return const SizedBox.shrink();
    return _ChangedSection(
      icon: Icons.article_outlined,
      title: 'Content',
      children: rows,
    );
  }

  Widget _buildAttrsDiff() {
    return _ChangedSection(
      icon: Icons.tune_outlined,
      title: 'Attributes / Variants',
      children: [
        _DiffRow(
          'Entries',
          '${_liveAttrCount ?? 0}',
          '${_proposalAttrCount ?? 0}',
        ),
      ],
    );
  }

  // ── existing body ──────────────────────────────────────────────────────────

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
                errorBuilder: (_, _, _) => Container(
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

          // ── Content ────────────────────────────────────────────────────
          if (r.includedItems.isNotEmpty ||
              r.excludedItems.isNotEmpty ||
              r.beforeAfterPairs.isNotEmpty) ...[
            const SizedBox(height: 20),
            const _SectionLabel('Content'),
            if (r.includedItems.isNotEmpty) ...[
              const SizedBox(height: 12),
              _BulletList(label: "What's Included", items: r.includedItems),
            ],
            if (r.excludedItems.isNotEmpty) ...[
              const SizedBox(height: 12),
              _BulletList(label: "What's Excluded", items: r.excludedItems),
            ],
            if (r.beforeAfterPairs.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Before & After',
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textSecondary)),
              const SizedBox(height: 8),
              for (int i = 0; i < r.beforeAfterPairs.length; i++)
                _BeforeAfterPairRow(
                    pair: r.beforeAfterPairs[i], index: i + 1),
            ],
          ],

          // ── Attributes / Variants ───────────────────────────────────────
          if (_attrs == null) ...[
            const SizedBox(height: 20),
            const _SectionLabel('Attributes / Variants'),
            const SizedBox(height: 12),
            const Center(
              child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          ] else if (_attrs!.isNotEmpty) ...[
            const SizedBox(height: 20),
            const _SectionLabel('Attributes / Variants'),
            const SizedBox(height: 12),
            for (final attr in _attrs!)
              _AdminAttrRow(attr: attr),
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

// ── Diff section widgets ──────────────────────────────────────────────────────

class _ChangedSection extends StatelessWidget {
  const _ChangedSection({
    required this.icon,
    required this.title,
    required this.children,
  });
  final IconData icon;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBE6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFFD666)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: const Color(0xFFB45309)),
              const SizedBox(width: 6),
              Text(
                title.toUpperCase(),
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFB45309),
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

class _DiffRow extends StatelessWidget {
  const _DiffRow(this.label, this.liveValue, this.proposedValue);
  final String label;
  final String liveValue;
  final String proposedValue;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary)),
          ),
          Expanded(
            child: Wrap(
              spacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(liveValue,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                      decoration: TextDecoration.lineThrough,
                    )),
                const Icon(Icons.arrow_forward_rounded,
                    size: 11, color: Color(0xFFB45309)),
                Text(proposedValue,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF78350F),
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DiffMultiLine extends StatelessWidget {
  const _DiffMultiLine({
    required this.label,
    required this.liveText,
    required this.proposedText,
  });
  final String label;
  final String? liveText;
  final String? proposedText;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          if (liveText != null && liveText!.isNotEmpty) ...[
            Text(liveText!,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  decoration: TextDecoration.lineThrough,
                )),
            const SizedBox(height: 2),
          ],
          Text(
            proposedText?.isNotEmpty == true ? proposedText! : '(cleared)',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF78350F),
            ),
          ),
        ],
      ),
    );
  }
}

class _DiffItemList extends StatelessWidget {
  const _DiffItemList({
    required this.label,
    required this.liveCount,
    required this.items,
  });
  final String label;
  final int liveCount;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(width: 6),
            Text(
              '$liveCount → ${items.length}',
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFB45309)),
            ),
          ]),
          const SizedBox(height: 4),
          ...items.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('• ',
                        style:
                            TextStyle(fontSize: 12, color: Color(0xFF92400E))),
                    Expanded(
                      child: Text(item,
                          style: const TextStyle(
                              fontSize: 12, color: Color(0xFF78350F))),
                    ),
                  ],
                ),
              )),
        ],
      ),
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

class _BulletList extends StatelessWidget {
  const _BulletList({required this.label, required this.items});
  final String label;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 13, color: AppColors.textSecondary)),
        const SizedBox(height: 6),
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('• ',
                    style: TextStyle(
                        fontSize: 13, color: AppColors.textSecondary)),
                Expanded(
                  child: Text(item,
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.textPrimary)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _BeforeAfterPairRow extends StatelessWidget {
  const _BeforeAfterPairRow({required this.pair, required this.index});
  final Map<String, String> pair;
  final int index;

  @override
  Widget build(BuildContext context) {
    final before = pair['before_url'] ?? '';
    final after = pair['after_url'] ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Pair $index',
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary)),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(child: _PairImage(label: 'Before', url: before)),
              const SizedBox(width: 10),
              Expanded(child: _PairImage(label: 'After', url: after)),
            ],
          ),
        ],
      ),
    );
  }
}

class _PairImage extends StatelessWidget {
  const _PairImage({required this.label, required this.url});
  final String label;
  final String url;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 11, color: AppColors.textSecondary)),
        const SizedBox(height: 4),
        if (url.isEmpty)
          Container(
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Center(
              child: Text('—',
                  style: TextStyle(color: AppColors.textSecondary)),
            ),
          )
        else
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.network(
              url,
              height: 80,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                height: 80,
                color: AppColors.border,
                child: const Icon(Icons.broken_image_outlined,
                    color: AppColors.textSecondary),
              ),
            ),
          ),
      ],
    );
  }
}

class _AdminAttrRow extends StatelessWidget {
  const _AdminAttrRow({required this.attr});
  final Map<String, dynamic> attr;

  @override
  Widget build(BuildContext context) {
    final opts =
        (attr['service_attribute_options'] as List<dynamic>?) ?? [];
    final price = opts.isNotEmpty
        ? (opts.first as Map<String, dynamic>)['price_adjustment'] as num?
        : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(attr['name'] as String? ?? '—',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary)),
            ),
            if (price != null && price > 0)
              Text('₹${price.toStringAsFixed(0)}',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
          ],
        ),
      ),
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
