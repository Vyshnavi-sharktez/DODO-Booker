import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../domain/models/catalog_service.dart';
import '../providers/services_provider.dart';

/// Read-only service detail dialog for vendors.
///
/// Mirrors the Customer App's ServiceDetailModal layout but strips all booking
/// actions (Book Now, Add to Cart, wishlist, AMC selection, reviews).
/// Opened from the "View" button on individual bookable products in the
/// All Services screen — does NOT add the service to vendor offerings.
class VendorServiceDetailDialog extends ConsumerWidget {
  const VendorServiceDetailDialog({super.key, required this.service});

  final CatalogService service;

  static Future<void> show(BuildContext context, CatalogService service) {
    final isNarrow = MediaQuery.of(context).size.width < 600;

    if (isNarrow) {
      return showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _BottomSheetContent(service: service),
      );
    }

    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: '',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (ctx, _, __) =>
          VendorServiceDetailDialog(service: service),
      transitionBuilder: (ctx, anim, _, child) => FadeTransition(
        opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1.0).animate(
              CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final size = MediaQuery.of(context).size;
    final faqsAsync = ref.watch(vendorServiceFaqsProvider(service.id));

    return Focus(
      autofocus: true,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          Navigator.of(context).pop();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Stack(
        children: [
          // Dark backdrop — tapping dismisses
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              behavior: HitTestBehavior.opaque,
              child: const ColoredBox(color: Color(0x70000000)),
            ),
          ),

          Center(
            child: SizedBox(
              width: (size.width * 0.9).clamp(320.0, 760.0),
              height: size.height * 0.85,
              child: Material(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                clipBehavior: Clip.antiAlias,
                elevation: 20,
                shadowColor: Colors.black26,
                child: Column(
                  children: [
                    // Header bar — title + close button
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              service.name,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded,
                                size: 20, color: AppColors.textSecondary),
                            onPressed: () => Navigator.of(context).pop(),
                            padding: EdgeInsets.zero,
                            constraints:
                                const BoxConstraints(minWidth: 36, minHeight: 36),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: AppColors.border),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _InfoSection(service: service),
                            if (service.description?.isNotEmpty == true)
                              _DescSection(description: service.description!),
                            if (service.includedItems.isNotEmpty ||
                                service.excludedItems.isNotEmpty)
                              _InclusionsSection(
                                included: service.includedItems,
                                excluded: service.excludedItems,
                              ),
                            if (service.warrantyEnabled)
                              _WarrantySection(service: service),
                            _FaqsSection(faqsAsync: faqsAsync),
                            const SizedBox(height: 28),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Mobile bottom sheet ────────────────────────────────────────────────────────

class _BottomSheetContent extends ConsumerWidget {
  const _BottomSheetContent({required this.service});
  final CatalogService service;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final faqsAsync = ref.watch(vendorServiceFaqsProvider(service.id));
    final maxHeight = MediaQuery.of(context).size.height * 0.92;

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 6),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Title + close
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    service.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded,
                      size: 20, color: AppColors.textSecondary),
                  onPressed: () => Navigator.of(context).pop(),
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 36, minHeight: 36),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          // Scrollable content
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _InfoSection(service: service),
                  if (service.description?.isNotEmpty == true)
                    _DescSection(description: service.description!),
                  if (service.includedItems.isNotEmpty ||
                      service.excludedItems.isNotEmpty)
                    _InclusionsSection(
                      included: service.includedItems,
                      excluded: service.excludedItems,
                    ),
                  if (service.warrantyEnabled)
                    _WarrantySection(service: service),
                  _FaqsSection(faqsAsync: faqsAsync),
                  const SizedBox(height: 28),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Info section ───────────────────────────────────────────────────────────────

class _InfoSection extends StatelessWidget {
  const _InfoSection({required this.service});
  final CatalogService service;

  @override
  Widget build(BuildContext context) {
    final hasRating = (service.rating ?? 0) > 0;
    final hasDiscount = service.hasDiscount;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Category badge
          if (service.parentName != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(100),
              ),
              child: Text(
                service.parentName!,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),

          if (hasRating) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.star_rounded, size: 15, color: Color(0xFFFBBC04)),
                const SizedBox(width: 3),
                Text(
                  service.rating!.toStringAsFixed(1),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFFBBC04),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '(${service.reviewCount} reviews)',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ],

          const SizedBox(height: 10),

          // Price row
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (hasDiscount) ...[
                Text(
                  '₹${service.basePrice.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textHint,
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '₹${service.finalPrice.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    height: 1.1,
                  ),
                ),
              ] else
                Text(
                  '₹${service.basePrice.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    height: 1.1,
                  ),
                ),
              if (service.estimatedDuration != null) ...[
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.schedule_rounded,
                          size: 12, color: AppColors.textSecondary),
                      const SizedBox(width: 4),
                      Text(
                        _formatDuration(service.estimatedDuration!),
                        style: const TextStyle(
                            fontSize: 11.5, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),

          const SizedBox(height: 16),
          const Divider(height: 1, color: AppColors.border),
        ],
      ),
    );
  }

  String _formatDuration(int minutes) {
    if (minutes < 60) return '$minutes min';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }
}

// ── Description section ────────────────────────────────────────────────────────

class _DescSection extends StatelessWidget {
  const _DescSection({required this.description});
  final String description;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'About this service',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: const TextStyle(
              fontSize: 13.5,
              color: AppColors.textSecondary,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: AppColors.border),
        ],
      ),
    );
  }
}

// ── Inclusions / Exclusions ────────────────────────────────────────────────────

class _InclusionsSection extends StatelessWidget {
  const _InclusionsSection({
    required this.included,
    required this.excluded,
  });
  final List<String> included;
  final List<String> excluded;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (included.isNotEmpty) _ItemList(items: included, isIncluded: true),
          if (included.isNotEmpty && excluded.isNotEmpty)
            const SizedBox(height: 16),
          if (excluded.isNotEmpty) _ItemList(items: excluded, isIncluded: false),
          const SizedBox(height: 16),
          const Divider(height: 1, color: AppColors.border),
        ],
      ),
    );
  }
}

class _ItemList extends StatelessWidget {
  const _ItemList({required this.items, required this.isIncluded});
  final List<String> items;
  final bool isIncluded;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isIncluded ? "What's Included" : "What's Excluded",
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: isIncluded ? AppColors.success : AppColors.error,
          ),
        ),
        const SizedBox(height: 8),
        ...items.map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    isIncluded
                        ? Icons.check_circle_rounded
                        : Icons.cancel_rounded,
                    size: 14,
                    color: isIncluded
                        ? AppColors.success
                        : AppColors.error,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      item,
                      style: const TextStyle(
                          fontSize: 12.5, color: AppColors.textSecondary, height: 1.4),
                    ),
                  ),
                ],
              ),
            )),
      ],
    );
  }
}

// ── Warranty ───────────────────────────────────────────────────────────────────

class _WarrantySection extends StatelessWidget {
  const _WarrantySection({required this.service});
  final CatalogService service;

  @override
  Widget build(BuildContext context) {
    final days = service.warrantyDays;
    final label = days == null
        ? 'Service Warranty'
        : days < 30
            ? '$days-day Warranty'
            : days < 365
                ? '${days ~/ 30}-month Warranty'
                : '${days ~/ 365}-year Warranty';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: AppColors.success.withAlpha(20),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.shield_rounded,
                    size: 16, color: AppColors.success),
              ),
              const SizedBox(width: 10),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          if (service.warrantyCovers?.isNotEmpty == true) ...[
            const SizedBox(height: 8),
            Text(
              'Covers: ${service.warrantyCovers}',
              style: const TextStyle(
                  fontSize: 12.5, color: AppColors.textSecondary, height: 1.5),
            ),
          ],
          if (service.warrantyExclusions?.isNotEmpty == true) ...[
            const SizedBox(height: 4),
            Text(
              'Excludes: ${service.warrantyExclusions}',
              style: const TextStyle(
                  fontSize: 12.5, color: AppColors.textHint, height: 1.5),
            ),
          ],
          const SizedBox(height: 16),
          const Divider(height: 1, color: AppColors.border),
        ],
      ),
    );
  }
}

// ── FAQs section ───────────────────────────────────────────────────────────────

class _FaqsSection extends StatelessWidget {
  const _FaqsSection({required this.faqsAsync});
  final AsyncValue<List<({String question, String answer})>> faqsAsync;

  @override
  Widget build(BuildContext context) {
    return faqsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
            child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2))),
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (faqs) {
        if (faqs.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Frequently Asked Questions',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              ...faqs.map((faq) => _FaqItem(faq: faq)),
            ],
          ),
        );
      },
    );
  }
}

class _FaqItem extends StatefulWidget {
  const _FaqItem({required this.faq});
  final ({String question, String answer}) faq;

  @override
  State<_FaqItem> createState() => _FaqItemState();
}

class _FaqItemState extends State<_FaqItem> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 1, thickness: 0.8, color: AppColors.border),
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          mouseCursor: SystemMouseCursors.click,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    widget.faq.question,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedRotation(
                  turns: _expanded ? 0.5 : 0.0,
                  duration: const Duration(milliseconds: 180),
                  child: const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              widget.faq.answer,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.55,
              ),
            ),
          ),
      ],
    );
  }
}
