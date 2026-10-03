import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/utils/service_image_registry.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../models/banner_model.dart';
import '../../../models/coupon_model.dart';
import '../../../routes/app_router.dart';
import '../../booking/services/coupon_providers.dart';
import '../../catalog/models/catalog_node_model.dart';
import '../../catalog/services/catalog_service.dart';
import '../../catalog/utils/catalog_launcher.dart';
import '../models/landing_page_section.dart';
import '../services/home_providers.dart';
import '../services/home_service.dart';
import 'how_it_works_section.dart';

// ── Mobile Promo Banner (first section, above CMS sections) ──────────────────
//
// Uses activeCouponsProvider — the real data source. Renders nothing if empty.
// Single coupon: plain card. Multiple: PageView + dots + 5s auto-scroll.

class MobilePromoBanner extends ConsumerStatefulWidget {
  const MobilePromoBanner({super.key});

  @override
  ConsumerState<MobilePromoBanner> createState() => _MobilePromoBannerState();
}

class _MobilePromoBannerState extends ConsumerState<MobilePromoBanner> {
  late final PageController _pageCtrl;
  Timer? _autoTimer;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController();
  }

  void _ensureTimer(int count) {
    if (_autoTimer != null || count <= 1) return;
    _autoTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || !_pageCtrl.hasClients) return;
      final next = (_page + 1) % count;
      _pageCtrl.animateToPage(next,
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeInOut);
    });
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final couponsAsync = ref.watch(activeCouponsProvider);
    return couponsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (coupons) {
        if (coupons.isEmpty) return const SizedBox.shrink();
        _ensureTimer(coupons.length);
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 148,
                child: coupons.length == 1
                    ? _PromoCouponCard(coupon: coupons.first)
                    : PageView.builder(
                        controller: _pageCtrl,
                        physics: const BouncingScrollPhysics(),
                        itemCount: coupons.length,
                        onPageChanged: (i) => setState(() => _page = i),
                        itemBuilder: (_, i) =>
                            _PromoCouponCard(coupon: coupons[i]),
                      ),
              ),
              if (coupons.length > 1) ...[
                const SizedBox(height: 10),
                _PromoDotIndicator(count: coupons.length, current: _page),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _PromoCouponCard extends StatefulWidget {
  final CouponModel coupon;
  const _PromoCouponCard({required this.coupon});

  @override
  State<_PromoCouponCard> createState() => _PromoCouponCardState();
}

class _PromoCouponCardState extends State<_PromoCouponCard> {
  bool _loading = false;

  String get _headline {
    final d = widget.coupon.discountValue;
    final isInt = d == d.floorToDouble();
    final val = isInt ? d.toInt().toString() : d.toStringAsFixed(1);
    return widget.coupon.discountType == 'percentage' ? '$val% OFF' : '₹$val OFF';
  }

  String get _subtitle =>
      widget.coupon.description?.isNotEmpty == true
          ? widget.coupon.description!
          : widget.coupon.applicabilityLabel;

  Future<void> _onViewServices() async {
    if (widget.coupon.applicabilityType == 'all' ||
        widget.coupon.applicableNodeIds.isEmpty) {
      context.push(AppRoutes.search);
      return;
    }
    setState(() => _loading = true);
    final node = await CatalogService()
        .fetchNode(widget.coupon.applicableNodeIds.first);
    if (!mounted) return;
    setState(() => _loading = false);
    if (node == null) {
      context.push(AppRoutes.search);
      return;
    }
    // openCatalogNode handles routing:
    // - category/non-bookable node → CategoryExplorerScreen
    // - leaf bookable node (service/product) → detail sheet
    openCatalogNode(context, node);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Clipboard.setData(ClipboardData(text: widget.coupon.code));
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Code "${widget.coupon.code}" copied!'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ));
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFFF9F2), Color(0xFFFFF0D0)],
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.07),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Gold accent stripe
              Container(width: 4, color: AppColors.gold),
              // Left: text panel
              Expanded(
                flex: 56,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Accent line
                      Container(
                        width: 24,
                        height: 3,
                        decoration: BoxDecoration(
                          color: AppColors.gold,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Big headline: "10% OFF"
                      Text(
                        _headline,
                        style: GoogleFonts.poppins(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF1A1714),
                          height: 1.1,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      // Description
                      Expanded(
                        child: Text(
                          _subtitle,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: const Color(0xFF6E6A64),
                            height: 1.35,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Dark CTA
                      GestureDetector(
                        onTap: _loading ? null : _onViewServices,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 7),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A1714),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: _loading
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  'View Services →',
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                    height: 1.2,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Right: styled coupon visual
              Expanded(
                flex: 44,
                child: _PromoCouponVisual(coupon: widget.coupon),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PromoCouponVisual extends StatelessWidget {
  final CouponModel coupon;
  const _PromoCouponVisual({required this.coupon});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFD166), Color(0xFFFFA836)],
        ),
      ),
      child: Stack(
        children: [
          // Decorative circles
          Positioned(
            right: -20,
            top: -20,
            child: Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.15),
              ),
            ),
          ),
          Positioned(
            left: -12,
            bottom: -12,
            child: Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.1),
              ),
            ),
          ),
          // Coupon code pill centered
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'USE CODE',
                  style: GoogleFonts.inter(
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    color: Colors.white.withValues(alpha: 0.85),
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    coupon.code,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFFF5A623),
                      letterSpacing: 0.5,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 6),
                Icon(
                  Icons.content_copy_rounded,
                  size: 14,
                  color: Colors.white.withValues(alpha: 0.8),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PromoDotIndicator extends StatelessWidget {
  final int count;
  final int current;
  const _PromoDotIndicator({required this.count, required this.current});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final active = i == current;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: active ? 18 : 6,
          height: 6,
          decoration: BoxDecoration(
            color: active ? AppColors.gold : const Color(0xFFD8D3CA),
            borderRadius: BorderRadius.circular(3),
          ),
        );
      }),
    );
  }
}

// ── Public entry: renders a single section in mobile style ────────────────────

class MobileHomeSectionRenderer extends ConsumerWidget {
  final LandingPageSection section;

  const MobileHomeSectionRenderer({super.key, required this.section});

  void _openNode(BuildContext context, CatalogNodeModel node) {
    context.push(AppRoutes.categoryExplorer,
        extra: <String, dynamic>{'node': node});
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    switch (section.sectionType) {
      case 'service_grid':
        final nodes = ref.watch(featuredCatalogNodesProvider);
        return _MobileServicesSection(
          title: section.config['title'] as String? ?? section.sectionName,
          asyncNodes: nodes,
          onNodeTap: (n) => _openNode(context, n),
          onSeeAll: () => context.push(AppRoutes.search),
        );

      case 'sub_services':
        final nodes = ref.watch(newServicesProvider);
        return _MobileSubServicesSection(
          title: section.config['title'] as String? ?? section.sectionName,
          asyncNodes: nodes,
          onNodeTap: (n) => openCatalogNode(context, n),
          onSeeAll: () => context.push(AppRoutes.search),
        );

      case 'special_offers':
        final coupons = ref.watch(activeCouponsProvider);
        final hasOffers =
            coupons.isLoading || (coupons.asData?.value.isNotEmpty ?? false);
        if (!hasOffers) return const SizedBox.shrink();
        return _MobileOffersSection(asyncCoupons: coupons);

      case 'how_it_works':
        final rawSteps = section.config['steps'] as List?;
        final steps = rawSteps
            ?.map((e) => HowItWorksStep.fromMap(e as Map<String, dynamic>))
            .toList();
        return _MobileHowItWorksWrapper(
          title:
              section.config['title'] as String? ?? section.sectionName,
          steps: steps?.isNotEmpty == true ? steps : null,
        );

      case 'popular_near_you':
        final nodes = ref.watch(popularServicesProvider);
        return _MobilePopularSection(
          title: section.config['title'] as String? ?? section.sectionName,
          asyncNodes: nodes,
          onNodeTap: (n) => openCatalogNode(context, n),
          onSeeAll: () => context.push(AppRoutes.search),
        );

      case 'why_dodo':
        final rawItems = section.config['items'] as List?;
        return _MobileWhyDodoSection(
          title: section.config['title'] as String? ?? section.sectionName,
          rawItems: rawItems,
        );

      case 'testimonials':
        final reviews = ref.watch(homeReviewsProvider);
        return _MobileReviewsSection(asyncReviews: reviews);

      case 'mobile_promo_banner':
        return const _MobileDailyOfferBanner();

      default:
        return const SizedBox.shrink();
    }
  }
}

// ── Section header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onSeeAll;

  const _SectionHeader({required this.title, this.onSeeAll});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      child: Row(
        children: [
          Text(
            title,
            style: GoogleFonts.poppins(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const Spacer(),
          if (onSeeAll != null)
            GestureDetector(
              onTap: onSeeAll,
              child: Text(
                'See all →',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.gold,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Image placeholder ─────────────────────────────────────────────────────────

Widget _imagePlaceholder({double? width, double? height, double radius = 12}) {
  return Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: const Color(0xFFE5E0D8),
      borderRadius: BorderRadius.circular(radius),
    ),
  );
}

Widget _nodeImage(String? url, {double? width, double? height, double radius = 12, BoxFit fit = BoxFit.cover}) {
  if (url == null || url.isEmpty) {
    return _imagePlaceholder(width: width, height: height, radius: radius);
  }
  return ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    child: Image.network(
      url,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (_, _, _) =>
          _imagePlaceholder(width: width, height: height, radius: radius),
      loadingBuilder: (_, child, progress) =>
          progress == null ? child : _imagePlaceholder(width: width, height: height, radius: radius),
    ),
  );
}

// ── Our Services ──────────────────────────────────────────────────────────────

class _MobileServicesSection extends StatefulWidget {
  final String title;
  final AsyncValue<List<CatalogNodeModel>> asyncNodes;
  final ValueChanged<CatalogNodeModel> onNodeTap;
  final VoidCallback onSeeAll;

  const _MobileServicesSection({
    required this.title,
    required this.asyncNodes,
    required this.onNodeTap,
    required this.onSeeAll,
  });

  @override
  State<_MobileServicesSection> createState() => _MobileServicesSectionState();
}

class _MobileServicesSectionState extends State<_MobileServicesSection> {
  bool _expanded = false;

  static const _initialCount = 6;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        _SectionHeader(title: widget.title, onSeeAll: null),
        widget.asyncNodes.when(
          loading: () => _CategoryGridSkeleton(),
          error: (_, __) => const SizedBox.shrink(),
          data: (nodes) {
            if (nodes.isEmpty) return const SizedBox.shrink();

            // First _initialCount nodes by sort_order (hidden ones consume a
            // position slot but are not rendered).
            final initialSlots = nodes.take(_initialCount).toList();
            final visibleInitial = initialSlots
                .where((n) => n.availabilityStatus != 'hidden')
                .toList();

            // More only appears if at least one VISIBLE node exists beyond
            // position _initialCount. Hidden nodes past that point don't count.
            final hasMore = nodes.length > _initialCount &&
                nodes
                    .skip(_initialCount)
                    .any((n) => n.availabilityStatus != 'hidden');

            // Expanded state: all visible nodes across all positions.
            final allVisible = nodes
                .where((n) => n.availabilityStatus != 'hidden')
                .toList();

            final display = _expanded ? allVisible : visibleInitial;

            if (display.isEmpty) return const SizedBox.shrink();

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  GridView.count(
                    crossAxisCount: 3,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    childAspectRatio: 0.72,
                    children: [
                      ...display.map(
                        (n) => _CategoryGridItem(
                          node: n,
                          onTap: () => widget.onNodeTap(n),
                        ),
                      ),
                      if (!_expanded && hasMore)
                        _MoreGridItem(
                          onTap: () => setState(() => _expanded = true),
                        ),
                    ],
                  ),
                  if (_expanded && hasMore) ...[
                    const SizedBox(height: 16),
                    GestureDetector(
                      onTap: () => setState(() => _expanded = false),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEDE8DF),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'Show Less ↑',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

// ── Category Grid widgets ─────────────────────────────────────────────────────

class _CategoryGridItem extends StatelessWidget {
  final CatalogNodeModel node;
  final VoidCallback onTap;

  const _CategoryGridItem({required this.node, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final imgUrl = ServiceImageRegistry.resolveMobile(
        node.mobileImageUrl, node.imageUrl, node.name);
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFEDE8DF),
                borderRadius: BorderRadius.circular(14),
              ),
              clipBehavior: Clip.antiAlias,
              child: imgUrl.isNotEmpty
                  ? Image.network(
                      imgUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          _CategoryIconFallback(name: node.name),
                      loadingBuilder: (_, child, progress) =>
                          progress == null ? child : _CategoryIconFallback(name: node.name),
                    )
                  : _CategoryIconFallback(name: node.name),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            node.name,
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
        ],
      ),
    );
  }
}

class _CategoryIconFallback extends StatelessWidget {
  final String name;
  const _CategoryIconFallback({required this.name});

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

class _MoreGridItem extends StatelessWidget {
  final VoidCallback? onTap;
  const _MoreGridItem({this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFEDE8DF),
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.grid_view_rounded,
                size: 30,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'More',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
              height: 1.2,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _CategoryGridSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.9,
        children: List.generate(
          6,
          (_) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFEDE8DF),
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Container(
                height: 10,
                decoration: BoxDecoration(
                  color: const Color(0xFFE5E0D8),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Daily Offer Banner ────────────────────────────────────────────────────────

class _MobileDailyOfferBanner extends ConsumerWidget {
  const _MobileDailyOfferBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(homeBannersProvider);
    return async.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (banners) {
        if (banners.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: _BannerCard(banner: banners.first),
        );
      },
    );
  }
}

class _BannerCard extends StatelessWidget {
  final BannerModel banner;
  const _BannerCard({required this.banner});

  @override
  Widget build(BuildContext context) {
    final hasImage = banner.imageUrl != null && banner.imageUrl!.isNotEmpty;
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 120),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(18),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          if (hasImage)
            Positioned.fill(
              child: Image.network(
                banner.imageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          if (hasImage)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerRight,
                    end: Alignment.centerLeft,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.65),
                    ],
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.gold,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'DAILY OFFER',
                    style: GoogleFonts.poppins(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: Colors.black,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  banner.title,
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    height: 1.2,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (banner.subtitle != null &&
                    banner.subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    banner.subtitle!,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (banner.actionLabel != null &&
                    banner.actionLabel!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.gold,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      banner.actionLabel!,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sub Services ──────────────────────────────────────────────────────────────

class _MobileSubServicesSection extends StatelessWidget {
  final String title;
  final AsyncValue<List<CatalogNodeModel>> asyncNodes;
  final ValueChanged<CatalogNodeModel> onNodeTap;
  final VoidCallback onSeeAll;

  const _MobileSubServicesSection({
    required this.title,
    required this.asyncNodes,
    required this.onNodeTap,
    required this.onSeeAll,
  });

  @override
  Widget build(BuildContext context) {
    final nodes = asyncNodes.asData?.value ?? [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        _SectionHeader(title: title, onSeeAll: null),
        SizedBox(
          height: 155,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: nodes.isEmpty ? 4 : nodes.length,
            itemBuilder: (context, i) {
              if (nodes.isEmpty) return _SubCardSkeleton();
              return _SubServiceCard(
                  node: nodes[i], onTap: () => onNodeTap(nodes[i]));
            },
          ),
        ),
      ],
    );
  }
}

class _SubServiceCard extends StatelessWidget {
  final CatalogNodeModel node;
  final VoidCallback onTap;

  const _SubServiceCard({required this.node, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 112,
        margin: const EdgeInsets.only(right: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 112,
              height: 90,
              decoration: BoxDecoration(
                color: const Color(0xFFEDE8DF),
                borderRadius: BorderRadius.circular(12),
              ),
              clipBehavior: Clip.antiAlias,
              child: _nodeImage(ServiceImageRegistry.resolveMobile(node.mobileImageUrl, node.imageUrl, node.name), width: 112, height: 90, radius: 0),
            ),
            const SizedBox(height: 6),
            Text(
              node.name,
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (node.basePrice != null)
              Text(
                '₹${(node.finalPrice ?? node.basePrice)!.toInt()}',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SubCardSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 112,
      margin: const EdgeInsets.only(right: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 112,
            height: 90,
            decoration: BoxDecoration(
              color: const Color(0xFFEDE8DF),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Best Offers ───────────────────────────────────────────────────────────────

class _MobileOffersSection extends StatelessWidget {
  final AsyncValue<List<CouponModel>> asyncCoupons;

  const _MobileOffersSection({required this.asyncCoupons});

  @override
  Widget build(BuildContext context) {
    final coupons = asyncCoupons.asData?.value ?? [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        const _SectionHeader(title: 'Best Offers for You'),
        const SizedBox(height: 12),
        if (coupons.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _PromoCouponCardSkeleton(),
          )
        else
          _OffersBannerPager(coupons: coupons),
      ],
    );
  }
}

// Stateful pager for the offers section — same card style as MobilePromoBanner.
class _OffersBannerPager extends StatefulWidget {
  final List<CouponModel> coupons;
  const _OffersBannerPager({required this.coupons});

  @override
  State<_OffersBannerPager> createState() => _OffersBannerPagerState();
}

class _OffersBannerPagerState extends State<_OffersBannerPager> {
  late final PageController _ctrl;
  Timer? _timer;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = PageController();
    if (widget.coupons.length > 1) {
      _timer = Timer.periodic(const Duration(seconds: 5), (_) {
        if (!mounted || !_ctrl.hasClients) return;
        final next = (_page + 1) % widget.coupons.length;
        _ctrl.animateToPage(next,
            duration: const Duration(milliseconds: 420),
            curve: Curves.easeInOut);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 148,
          child: widget.coupons.length == 1
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _PromoCouponCard(coupon: widget.coupons.first),
                )
              : PageView.builder(
                  controller: _ctrl,
                  physics: const BouncingScrollPhysics(),
                  itemCount: widget.coupons.length,
                  onPageChanged: (i) => setState(() => _page = i),
                  itemBuilder: (_, i) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _PromoCouponCard(coupon: widget.coupons[i]),
                  ),
                ),
        ),
        if (widget.coupons.length > 1) ...[
          const SizedBox(height: 10),
          _PromoDotIndicator(
              count: widget.coupons.length, current: _page),
        ],
      ],
    );
  }
}

class _PromoCouponCardSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 148,
      decoration: BoxDecoration(
        color: const Color(0xFFF0EDE8),
        borderRadius: BorderRadius.circular(18),
      ),
    );
  }
}

// ── How It Works (thin wrapper that forces the mobile row) ────────────────────

class _MobileHowItWorksWrapper extends StatelessWidget {
  final String title;
  final List<HowItWorksStep>? steps;

  const _MobileHowItWorksWrapper({required this.title, this.steps});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: HowItWorksSection(title: title, steps: steps),
    );
  }
}

// ── Popular Services ──────────────────────────────────────────────────────────

class _MobilePopularSection extends StatelessWidget {
  final String title;
  final AsyncValue<List<CatalogNodeModel>> asyncNodes;
  final ValueChanged<CatalogNodeModel> onNodeTap;
  final VoidCallback onSeeAll;

  const _MobilePopularSection({
    required this.title,
    required this.asyncNodes,
    required this.onNodeTap,
    required this.onSeeAll,
  });

  @override
  Widget build(BuildContext context) {
    final nodes = asyncNodes.asData?.value ?? [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        _SectionHeader(title: title, onSeeAll: null),
        SizedBox(
          height: 165,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: nodes.isEmpty ? 3 : nodes.length,
            itemBuilder: (context, i) {
              if (nodes.isEmpty) return _PopularCardSkeleton();
              return _PopularCard(
                  node: nodes[i], onTap: () => onNodeTap(nodes[i]));
            },
          ),
        ),
      ],
    );
  }
}

class _PopularCard extends StatelessWidget {
  final CatalogNodeModel node;
  final VoidCallback onTap;

  const _PopularCard({required this.node, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final price = node.basePrice;
    final rating = node.rating > 0 ? node.rating.toStringAsFixed(1) : null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 130,
        margin: const EdgeInsets.only(right: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 130,
              height: 110,
              decoration: BoxDecoration(
                color: const Color(0xFFEDE8DF),
                borderRadius: BorderRadius.circular(12),
              ),
              clipBehavior: Clip.antiAlias,
              child: _nodeImage(ServiceImageRegistry.resolveMobile(node.mobileImageUrl, node.imageUrl, node.name), width: 130, height: 110, radius: 0),
            ),
            const SizedBox(height: 6),
            Text(
              node.name,
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              [
                if (price != null) '₹${price.toInt()}',
                if (rating != null) '$rating★',
              ].join(' - '),
              style: GoogleFonts.inter(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PopularCardSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 130,
      margin: const EdgeInsets.only(right: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 130,
            height: 110,
            decoration: BoxDecoration(
              color: const Color(0xFFEDE8DF),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Why Choose DODO (horizontal chips) ───────────────────────────────────────

const _kWhyDodoChips = [
  _WhyChip(icon: Icons.verified_outlined, label: 'Verified\nProfessionals'),
  _WhyChip(icon: Icons.sell_outlined, label: 'Transparent\nPricing'),
  _WhyChip(icon: Icons.access_time_rounded, label: 'On-Time\nService'),
  _WhyChip(icon: Icons.headset_mic_outlined, label: '24/7\nSupport'),
];

class _WhyChip {
  final IconData icon;
  final String label;
  const _WhyChip({required this.icon, required this.label});
}

class _MobileWhyDodoSection extends StatelessWidget {
  final String title;
  final List<dynamic>? rawItems;

  const _MobileWhyDodoSection({required this.title, this.rawItems});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
          child: Text(
            title,
            style: GoogleFonts.poppins(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: GridView.count(
            crossAxisCount: 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 2.6,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: _kWhyDodoChips
                .map((chip) => _WhyDodoChipWidget(chip: chip))
                .toList(),
          ),
        ),
        const SizedBox(height: 4),
      ],
    );
  }
}

class _WhyDodoChipWidget extends StatelessWidget {
  final _WhyChip chip;
  const _WhyDodoChipWidget({required this.chip});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF2EFE9),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(chip.icon, size: 18, color: AppColors.textPrimary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              chip.label,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Customer Reviews ──────────────────────────────────────────────────────────

class _MobileReviewsSection extends StatelessWidget {
  final AsyncValue<List<PublicReview>> asyncReviews;

  const _MobileReviewsSection({required this.asyncReviews});

  @override
  Widget build(BuildContext context) {
    return asyncReviews.when(
      loading: () => _shell(child: _skeletons()),
      error: (_, __) => const SizedBox.shrink(),
      data: (reviews) => reviews.isEmpty
          ? _shell(child: _emptyState(context))
          : _shell(child: _cards(reviews)),
    );
  }

  Widget _shell({required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        const _SectionHeader(title: 'What our customers say'),
        child,
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _cards(List<PublicReview> reviews) {
    return SizedBox(
      height: 170,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: reviews.length,
        itemBuilder: (_, i) => _ReviewCard(review: reviews[i]),
      ),
    );
  }

  Widget _skeletons() {
    return SizedBox(
      height: 170,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: 3,
        itemBuilder: (_, __) => _ReviewCardSkeleton(),
      ),
    );
  }

  Widget _emptyState(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFECE7DE), width: 0.8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.star_outline_rounded,
                size: 28, color: AppColors.gold),
            const SizedBox(height: 8),
            Text(
              'Be the first to share your experience!',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  final PublicReview review;
  const _ReviewCard({required this.review});

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.sizeOf(context).width;
    final cardW = (screenW * 0.72).clamp(200.0, 280.0);

    return Container(
      width: cardW,
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFECE7DE), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Stars + rating
          Row(
            children: [
              ...List.generate(5, (i) => Icon(
                i < review.rating ? Icons.star_rounded : Icons.star_outline_rounded,
                size: 14,
                color: AppColors.gold,
              )),
              const SizedBox(width: 6),
              Text(
                review.rating.toString(),
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Review text
          Expanded(
            child: Text(
              '"${review.reviewText}"',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: AppColors.textPrimary,
                height: 1.5,
              ),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 8),
          // Reviewer
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: const BoxDecoration(
                  color: Color(0xFFE5E0D8),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  review.initials,
                  style: GoogleFonts.poppins(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                review.customerName,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReviewCardSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      margin: const EdgeInsets.only(right: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFECE7DE), width: 0.8),
      ),
    );
  }
}
