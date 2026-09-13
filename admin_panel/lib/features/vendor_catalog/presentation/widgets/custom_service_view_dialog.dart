import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../service_faqs/presentation/widgets/custom_service_faqs_dialog.dart';
import '../../../vendor_service_requests/domain/models/vendor_service_request.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CustomServiceViewDialog — read-only view of a vendor custom service.
// Used for both the live service ("View") and a pending edit proposal ("View Proposed").
// ─────────────────────────────────────────────────────────────────────────────

class CustomServiceViewDialog extends StatefulWidget {
  final VendorServiceRequest service;
  final bool isProposal;

  const CustomServiceViewDialog({
    super.key,
    required this.service,
    this.isProposal = false,
  });

  static Future<void> show(
    BuildContext context, {
    required VendorServiceRequest service,
    bool isProposal = false,
  }) {
    return showDialog(
      context: context,
      builder: (_) => CustomServiceViewDialog(
        service: service,
        isProposal: isProposal,
      ),
    );
  }

  @override
  State<CustomServiceViewDialog> createState() =>
      _CustomServiceViewDialogState();
}

class _CustomServiceViewDialogState extends State<CustomServiceViewDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _db = Supabase.instance.client;

  bool _loading = true;
  List<String> _includedItems = [];
  List<String> _excludedItems = [];
  List<Map<String, String>> _beforeAfterPairs = [];
  List<Map<String, dynamic>> _attrs = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final row = await _db
          .from('vendor_service_requests')
          .select('included_items, excluded_items, before_after_pairs')
          .eq('id', widget.service.id)
          .single();

      final attrsData = await _db
          .from('service_attributes')
          .select('id, name, field_type, service_attribute_options('
              'id, option_name, price_adjustment, discount_type, discount_value, sort_order)')
          .eq('custom_service_id', widget.service.id)
          .order('name');

      if (!mounted) return;
      setState(() {
        _includedItems =
            List<String>.from((row['included_items'] as List<dynamic>?) ?? []);
        _excludedItems =
            List<String>.from((row['excluded_items'] as List<dynamic>?) ?? []);
        _beforeAfterPairs =
            ((row['before_after_pairs'] as List<dynamic>?) ?? [])
                .map((e) => Map<String, String>.from((e as Map)
                    .map((k, v) => MapEntry(k.toString(), v.toString()))))
                .toList();
        _attrs = List<Map<String, dynamic>>.from(attrsData as List);
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final svc = widget.service;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              decoration: const BoxDecoration(
                border: Border(
                    bottom: BorderSide(color: AppColors.border, width: 0.8)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.preview_rounded,
                      size: 20, color: AppColors.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                svc.serviceName,
                                style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimary),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (widget.isProposal) ...[
                              const SizedBox(width: 8),
                              const _ProposalChip(),
                            ],
                          ],
                        ),
                        Text(
                          svc.formattedActivePrice,
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded,
                        size: 20, color: AppColors.textSecondary),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Tab bar
            TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.textSecondary,
              indicatorColor: AppColors.primary,
              tabs: const [
                Tab(text: 'Overview'),
                Tab(text: 'Content'),
                Tab(text: 'Attributes'),
              ],
            ),

            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildOverviewTab(),
                        _buildContentTab(),
                        _buildAttributesTab(),
                      ],
                    ),
            ),

            // Footer
            Container(
              decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: AppColors.border))),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: () => CustomServiceFaqsDialog.show(
                      context,
                      customServiceId: svc.id,
                      serviceName: svc.serviceName,
                    ),
                    icon: const Icon(Icons.quiz_outlined, size: 15),
                    label: const Text('FAQs'),
                    style: TextButton.styleFrom(
                        foregroundColor: AppColors.textSecondary),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 10),
                    ),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewTab() {
    final svc = widget.service;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (svc.imageUrl != null && svc.imageUrl!.isNotEmpty) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(
                svc.imageUrl!,
                height: 160,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
            const SizedBox(height: 16),
          ],
          _ReadRow(label: 'Name', value: svc.serviceName),
          if (svc.description != null && svc.description!.isNotEmpty)
            _ReadRow(label: 'Description', value: svc.description!),
          _ReadRow(label: 'Price', value: svc.formattedActivePrice),
          _ReadRow(label: 'Status', value: svc.statusLabel),
          _ReadRow(label: 'Vendor', value: svc.vendorName),
          if (svc.vendorTier != null)
            _ReadRow(label: 'Tier', value: svc.vendorTier!),
          _ReadRow(label: 'Created', value: svc.formattedDate),
          const SizedBox(height: 20),
          const Divider(color: AppColors.border),
          const SizedBox(height: 16),
          Row(
            children: const [
              Icon(Icons.verified_outlined, size: 15, color: AppColors.primary),
              SizedBox(width: 6),
              Text('Warranty',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
            ],
          ),
          const SizedBox(height: 12),
          if (!svc.warrantyEnabled)
            const Text('No warranty configured.',
                style: TextStyle(
                    fontSize: 13, color: AppColors.textSecondary))
          else ...[
            _ReadRow(
                label: 'Duration', value: '${svc.warrantyDays ?? 0} days'),
            if (svc.warrantyCovers != null &&
                svc.warrantyCovers!.isNotEmpty)
              _ReadRow(label: 'Covers', value: svc.warrantyCovers!),
            if (svc.warrantyExclusions != null &&
                svc.warrantyExclusions!.isNotEmpty)
              _ReadRow(
                  label: 'Does not cover', value: svc.warrantyExclusions!),
          ],
        ],
      ),
    );
  }

  Widget _buildContentTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ReadSection(
            icon: Icons.check_circle_outline_rounded,
            color: AppColors.success,
            label: "What's Included",
            items: _includedItems,
          ),
          const SizedBox(height: 24),
          const Divider(color: AppColors.border),
          const SizedBox(height: 20),
          _ReadSection(
            icon: Icons.cancel_outlined,
            color: AppColors.error,
            label: "What's Excluded",
            items: _excludedItems,
          ),
          if (_beforeAfterPairs.isNotEmpty) ...[
            const SizedBox(height: 24),
            const Divider(color: AppColors.border),
            const SizedBox(height: 20),
            const Row(
              children: [
                Icon(Icons.compare_rounded,
                    size: 15, color: AppColors.accent),
                SizedBox(width: 6),
                Text('Before & After',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
              ],
            ),
            const SizedBox(height: 12),
            ...List.generate(_beforeAfterPairs.length, (i) {
              final pair = _beforeAfterPairs[i];
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Pair ${i + 1}',
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: _ImagePreview(
                              label: 'Before',
                              url: pair['before_url'] ?? ''),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _ImagePreview(
                              label: 'After', url: pair['after_url'] ?? ''),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildAttributesTab() {
    if (_attrs.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.tune_outlined,
                size: 40, color: AppColors.textSecondary),
            SizedBox(height: 12),
            Text('No attributes / variants.',
                style: TextStyle(color: AppColors.textSecondary)),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _attrs.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final attr = _attrs[i];
        final name = attr['name'] as String? ?? '';
        final opts =
            (attr['service_attribute_options'] as List<dynamic>?) ?? [];
        final firstOpt = opts.isNotEmpty ? opts.first as Map : null;
        final price =
            (firstOpt?['price_adjustment'] as num?)?.toDouble() ?? 0.0;
        final discType =
            firstOpt?['discount_type'] as String? ?? 'percentage';
        final discVal =
            (firstOpt?['discount_value'] as num?)?.toDouble() ?? 0.0;

        return Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: AppColors.textPrimary)),
              if (price > 0) ...[
                const SizedBox(height: 2),
                Text('₹${price.toStringAsFixed(0)}',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
              ],
              if (discVal > 0) ...[
                const SizedBox(height: 2),
                Text(
                  discType == 'percentage'
                      ? '${discVal.toStringAsFixed(0)}% discount'
                      : '₹${discVal.toStringAsFixed(0)} off',
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.success),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

class _ProposalChip extends StatelessWidget {
  const _ProposalChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFFFCA28)),
      ),
      child: const Text(
        'Proposed Edit',
        style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: Color(0xFFF57F17)),
      ),
    );
  }
}

class _ReadRow extends StatelessWidget {
  const _ReadRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }
}

class _ReadSection extends StatelessWidget {
  const _ReadSection({
    required this.icon,
    required this.color,
    required this.label,
    required this.items,
  });
  final IconData icon;
  final Color color;
  final String label;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 6),
            Text(label,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
          ],
        ),
        const SizedBox(height: 8),
        if (items.isEmpty)
          const Text('None.',
              style:
                  TextStyle(fontSize: 13, color: AppColors.textSecondary))
        else
          ...items.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon,
                        size: 11, color: color.withValues(alpha: 0.7)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(item,
                          style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textPrimary)),
                    ),
                  ],
                ),
              )),
      ],
    );
  }
}

class _ImagePreview extends StatelessWidget {
  const _ImagePreview({required this.label, required this.url});
  final String label;
  final String url;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary)),
        const SizedBox(height: 4),
        if (url.isEmpty)
          Container(
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Center(
              child: Text('No image',
                  style: TextStyle(
                      fontSize: 11, color: AppColors.textSecondary)),
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
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Center(
                    child: Icon(Icons.broken_image_outlined,
                        color: AppColors.textSecondary)),
              ),
            ),
          ),
      ],
    );
  }
}
