import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/horizontal_carousel.dart';
import '../../../core/widgets/section_header.dart';
import '../models/vcs_category_model.dart';
import '../providers/vcs_providers.dart';
import '../../../routes/app_router.dart';

// ── Layout constants (mirrors sub_services_section.dart) ─────────────────────

const double _kCardW  = 240.0;
const double _kImgH   = 180.0;
const double _kLabelH = 52.0;
const double _kCardH  = _kImgH + _kLabelH;
const double _kGap    = 16.0;
const double _kRadius = 16.0;

// ── Public entry point ────────────────────────────────────────────────────────

class VendorCatalogSection extends StatelessWidget {
  const VendorCatalogSection({super.key, this.title});
  final String? title;

  @override
  Widget build(BuildContext context) => _SectionBody(title: title);
}

// ── Section body ──────────────────────────────────────────────────────────────

class _SectionBody extends ConsumerWidget {
  const _SectionBody({this.title});
  final String? title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catsAsync = ref.watch(vcsCategoriesProvider);
    final isMobile = MediaQuery.sizeOf(context).width < 768;

    if (isMobile) {
      return _MobileVendorServicesSection(
        title: title ?? 'Vendor Services',
        catsAsync: catsAsync,
      );
    }

    return catsAsync.maybeWhen(
      data: (cats) {
        if (cats.isEmpty) return const SizedBox.shrink();
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: SectionHeader(title: title ?? 'Vendor Services'),
            ),
            const SizedBox(height: 20),
            HorizontalCarousel(
              height: _kCardH + 16,
              itemCount: cats.length,
              scrollStep: 3 * (_kCardW + _kGap),
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              itemBuilder: (_, i) => Padding(
                padding: EdgeInsets.only(right: i < cats.length - 1 ? _kGap : 0),
                child: _CategoryCard(category: cats[i]),
              ),
            ),
          ],
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

// ── Mobile section (matches Our Services _MobileServicesSection) ──────────────

class _MobileVendorServicesSection extends StatefulWidget {
  const _MobileVendorServicesSection({
    required this.title,
    required this.catsAsync,
  });

  final String title;
  final AsyncValue<List<VcsCategoryModel>> catsAsync;

  @override
  State<_MobileVendorServicesSection> createState() =>
      _MobileVendorServicesSectionState();
}

class _MobileVendorServicesSectionState
    extends State<_MobileVendorServicesSection> {
  bool _expanded = false;

  static const _initialCount = 6;

  @override
  Widget build(BuildContext context) {
    return widget.catsAsync.maybeWhen(
      data: (cats) {
        if (cats.isEmpty) return const SizedBox.shrink();

        final hasMore = cats.length > _initialCount;
        final display =
            _expanded ? cats : cats.take(_initialCount).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
              child: Text(
                widget.title,
                style: GoogleFonts.poppins(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  AnimatedSize(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    alignment: Alignment.topCenter,
                    child: GridView.count(
                      crossAxisCount: 3,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                      childAspectRatio: 0.72,
                      children: display
                          .map((cat) => _MobileCategoryGridItem(category: cat))
                          .toList(),
                    ),
                  ),
                  if (hasMore) ...[
                    const SizedBox(height: 16),
                    Center(
                      child: GestureDetector(
                        onTap: () =>
                            setState(() => _expanded = !_expanded),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF5F0E8),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: const Color(0xFFDED5C4),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _expanded ? 'Show Less' : 'Show More',
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(width: 4),
                              AnimatedRotation(
                                turns: _expanded ? 0.5 : 0,
                                duration:
                                    const Duration(milliseconds: 300),
                                child: const Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  size: 18,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                ],
              ),
            ),
          ],
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _MobileCategoryGridItem extends StatelessWidget {
  const _MobileCategoryGridItem({required this.category});
  final VcsCategoryModel category;

  @override
  Widget build(BuildContext context) {
    final imgUrl = category.imageUrl;
    return GestureDetector(
      onTap: () => context.push(
        AppRoutes.vcVendorList.replaceFirst(':categoryId', category.id),
        extra: category.name,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFEDE8DF),
                borderRadius: BorderRadius.circular(14),
              ),
              clipBehavior: Clip.antiAlias,
              child: (imgUrl?.isNotEmpty ?? false)
                  ? Image.network(
                      imgUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          _MobileCategoryFallback(name: category.name),
                      loadingBuilder: (_, child, progress) =>
                          progress == null
                              ? child
                              : _MobileCategoryFallback(name: category.name),
                    )
                  : _MobileCategoryFallback(name: category.name),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 34,
            child: Text(
              category.name,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
                height: 1.2,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileCategoryFallback extends StatelessWidget {
  const _MobileCategoryFallback({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFEDE8DF),
      alignment: Alignment.center,
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: GoogleFonts.poppins(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

// ── Category card (240 × (180 image + 52 label)) ─────────────────────────────

class _CategoryCard extends StatefulWidget {
  const _CategoryCard({required this.category});
  final VcsCategoryModel category;

  @override
  State<_CategoryCard> createState() => _CategoryCardState();
}

class _CategoryCardState extends State<_CategoryCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cat = widget.category;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () => context.push(
          AppRoutes.vcVendorList.replaceFirst(':categoryId', cat.id),
          extra: cat.name,
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          width: _kCardW,
          height: _kCardH,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(_kRadius),
            border: Border.all(
              color: _hovered
                  ? AppColors.gold.withAlpha(140)
                  : const Color(0xFFECE7DE),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(_hovered ? 18 : 8),
                blurRadius: _hovered ? 16 : 6,
                offset: Offset(0, _hovered ? 6 : 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(_kRadius - 1),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Image
                SizedBox(
                  height: _kImgH,
                  child: cat.imageUrl != null
                      ? Image.network(
                          cat.imageUrl!,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          loadingBuilder: (_, child, p) =>
                              p == null ? child : const ColoredBox(color: Color(0xFFF1ECE1)),
                          errorBuilder: (_, __, ___) => const _Placeholder(),
                        )
                      : const _Placeholder(),
                ),
                // Label strip
                SizedBox(
                  height: _kLabelH,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          cat.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF1A1714),
                            height: 1.25,
                          ),
                        ),
                        if (cat.vendorCount > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              '${cat.vendorCount} vendor${cat.vendorCount == 1 ? '' : 's'}',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF1A1714),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Placeholder image ─────────────────────────────────────────────────────────

class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) => Container(
        color: const Color(0xFFF1ECE1),
        alignment: Alignment.center,
        child: const Icon(
          Icons.storefront_rounded,
          size: 32,
          color: AppColors.gold,
        ),
      );
}
