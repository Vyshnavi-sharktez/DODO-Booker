import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_header.dart';
import '../../profile/utils/profile_launcher.dart';
import '../../vendor_catalog/screens/vendor_detail_screen.dart';
import '../models/instahelp_vendor_model.dart';
import '../providers/instahelp_providers.dart';

const _kDiscounts = [
  (10, '10% and above'),
  (20, '20% and above'),
  (30, '30% and above'),
  (40, '40% and above'),
];

class InstaHelpVendorListScreen extends ConsumerStatefulWidget {
  const InstaHelpVendorListScreen({
    super.key,
    required this.lat,
    required this.lng,
    required this.initialTab,
  });

  final double lat;
  final double lng;
  final int initialTab;

  @override
  ConsumerState<InstaHelpVendorListScreen> createState() =>
      _InstaHelpVendorListScreenState();
}

class _InstaHelpVendorListScreenState
    extends ConsumerState<InstaHelpVendorListScreen> {
  double? _minRating;
  int? _minDiscount;
  RangeValues? _selectedPriceRange;
  double? _maxDistanceKm;
  bool _filterInstant = false;
  bool _filterSchedule = false;

  String get _moduleLabel {
    switch (widget.initialTab) {
      case 1:
        return 'Instant';
      case 2:
        return 'Car Wash';
      default:
        return 'Scheduled';
    }
  }

  static String _tabToModeType(int tab) {
    switch (tab) {
      case 1:
        return 'instant';
      case 2:
        return 'car_wash';
      default:
        return 'scheduled';
    }
  }

  void _clearAll() => setState(() {
        _minRating = null;
        _minDiscount = null;
        _selectedPriceRange = null;
        _maxDistanceKm = null;
        _filterInstant = false;
        _filterSchedule = false;
      });

  // ── Price bounds derived from loaded vendors ──────────────────────────────

  static (double, double) _priceBounds(List<InstaHelpVendorModel> vendors) {
    final prices = vendors
        .where((v) => v.minServicePrice != null && v.minServicePrice! > 0)
        .map((v) => v.minServicePrice!)
        .toList();
    if (prices.isEmpty) return (0.0, 1000.0);
    final minP = prices.reduce(math.min).floorToDouble();
    final maxP = prices.reduce(math.max).ceilToDouble();
    if (minP >= maxP) return (0.0, maxP + 1000.0);
    return (minP, maxP);
  }

  static bool _isPriceFilterActive(
    List<InstaHelpVendorModel> vendors,
    RangeValues? range,
  ) {
    if (range == null) return false;
    final (sMin, sMax) = _priceBounds(vendors);
    return range.start.round() > sMin.round() ||
        range.end.round() < sMax.round();
  }

  static RangeValues _resolvePriceRange(
    RangeValues? selected,
    double sliderMin,
    double sliderMax,
  ) {
    if (selected == null) return RangeValues(sliderMin, sliderMax);
    final s = selected.start.clamp(sliderMin, sliderMax);
    final e = selected.end.clamp(s, sliderMax);
    return RangeValues(s, e);
  }

  static double _maxDistanceBound(List<InstaHelpVendorModel> vendors) {
    final dists = vendors
        .where((v) => v.distanceKm != null)
        .map((v) => v.distanceKm!)
        .toList();
    if (dists.isEmpty) return 50.0;
    return math.max(dists.reduce(math.max).ceilToDouble(), 5.0);
  }

  int _activeFilterCount(List<InstaHelpVendorModel> vendors) =>
      (_minRating != null ? 1 : 0) +
      (_minDiscount != null ? 1 : 0) +
      (_isPriceFilterActive(vendors, _selectedPriceRange) ? 1 : 0) +
      (_maxDistanceKm != null ? 1 : 0) +
      (_filterInstant ? 1 : 0) +
      (_filterSchedule ? 1 : 0);

  List<InstaHelpVendorModel> _filtered(List<InstaHelpVendorModel> vendors) {
    var list = [...vendors];

    if (_minRating != null) {
      list = list.where((v) => (v.rating ?? 0) >= _minRating!).toList();
    }
    if (_minDiscount != null) {
      list = list
          .where((v) => v.maxDiscountPercent >= _minDiscount!)
          .toList();
    }
    if (_isPriceFilterActive(vendors, _selectedPriceRange)) {
      final (sMin, sMax) = _priceBounds(vendors);
      final range =
          _resolvePriceRange(_selectedPriceRange, sMin, sMax);
      final minP = range.start.round();
      final maxP = range.end.round();
      list = list.where((v) {
        final p = v.minServicePrice;
        if (p == null) return true;
        return p.round() >= minP && p.round() <= maxP;
      }).toList();
    }
    if (_maxDistanceKm != null) {
      list = list
          .where(
              (v) => v.distanceKm == null || v.distanceKm! <= _maxDistanceKm!)
          .toList();
    }
    if (_filterInstant) {
      list = list.where((v) => v.instantAvailable).toList();
    }
    if (_filterSchedule) {
      list = list.where((v) => v.scheduleAvailable).toList();
    }

    return list;
  }

  void _onVendorTap(BuildContext context, InstaHelpVendorModel vendor) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => VendorDetailScreen(
          vendorId: vendor.id,
          vendorName: vendor.businessName,
          initialVendor: vendor.toVcsModel(),
          showInstaHelp: true,
          initialInstaHelpTab: widget.initialTab,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final key = (lat: widget.lat, lng: widget.lng, modeType: _tabToModeType(widget.initialTab));
    final vendorsAsync = ref.watch(instaHelpVendorsProvider(key));
    final allVendors = vendorsAsync.asData?.value ?? const [];
    final activeCount = _activeFilterCount(allVendors);
    final isWide = MediaQuery.sizeOf(context).width >= 768;

    // ── Desktop UI ─────────────────────────────────────────────────────────
    if (isWide) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppHeader(
          onLogoTap: () {
            Navigator.of(context).popUntil((r) => r.isFirst);
            context.go('/');
          },
          onProfileTap: () => openProfile(context),
        ),
        body: Column(
          children: [
            _SubHeader(
              moduleLabel: _moduleLabel,
              vendorCount: vendorsAsync.asData?.value != null
                  ? _filtered(vendorsAsync.asData!.value).length
                  : 0,
            ),
            const Divider(height: 1, color: AppColors.border),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _FilterSidebar(
                    minRating: _minRating,
                    onRatingChanged: (r) =>
                        setState(() => _minRating = r),
                    minDiscount: _minDiscount,
                    onDiscountChanged: (d) =>
                        setState(() => _minDiscount = d),
                    selectedPriceRange: _selectedPriceRange,
                    onPriceRangeChanged: (r) =>
                        setState(() => _selectedPriceRange = r),
                    maxDistanceKm: _maxDistanceKm,
                    onDistanceChanged: (d) =>
                        setState(() => _maxDistanceKm = d),
                    filterInstant: _filterInstant,
                    onInstantChanged: (v) =>
                        setState(() => _filterInstant = v),
                    filterSchedule: _filterSchedule,
                    onScheduleChanged: (v) =>
                        setState(() => _filterSchedule = v),
                    vendors: allVendors,
                    onClearAll: _clearAll,
                  ),
                  Expanded(
                    child: vendorsAsync.when(
                      skipLoadingOnReload: true,
                      loading: () => const Center(
                          child: CircularProgressIndicator()),
                      error: (e, _) =>
                          _ErrorState(message: e.toString()),
                      data: (vendors) {
                        final filtered = _filtered(vendors);
                        if (filtered.isEmpty) {
                          return _EmptyState(
                            hasFilters: activeCount > 0,
                            onClear: _clearAll,
                          );
                        }
                        return _VendorGrid(
                          vendors: filtered,
                          onTap: (v) => _onVendorTap(context, v),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // ── Mobile UI ──────────────────────────────────────────────────────────
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _MobileHeader(
              moduleLabel: _moduleLabel,
              vendorCount: allVendors.isNotEmpty
                  ? _filtered(allVendors).length
                  : 0,
              activeFilterCount: activeCount,
              onFilterTap: () =>
                  _openMobileFilters(context, allVendors),
            ),
            const Divider(height: 1, color: AppColors.border),
            Expanded(
              child: vendorsAsync.when(
                skipLoadingOnReload: true,
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => _ErrorState(message: e.toString()),
                data: (vendors) {
                  final filtered = _filtered(vendors);
                  if (filtered.isEmpty) {
                    return _EmptyState(
                      hasFilters: activeCount > 0,
                      onClear: _clearAll,
                    );
                  }
                  return _MobileVendorGrid(
                    vendors: filtered,
                    onTap: (v) => _onVendorTap(context, v),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openMobileFilters(
      BuildContext context, List<InstaHelpVendorModel> vendors) {
    double? tempMinRating = _minRating;
    int? tempMinDiscount = _minDiscount;
    RangeValues? tempPriceRange = _selectedPriceRange;
    double? tempMaxDistance = _maxDistanceKm;
    bool tempInstant = _filterInstant;
    bool tempSchedule = _filterSchedule;

    final parentMedia = MediaQuery.of(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        final sheetMedia = MediaQuery.of(sheetCtx);
        final screenHeight = sheetMedia.size.height;
        final topInset =
            math.max(parentMedia.padding.top, sheetMedia.padding.top);
        final bottomInset = math.max(
          math.max(parentMedia.padding.bottom,
              parentMedia.viewPadding.bottom),
          math.max(
              sheetMedia.padding.bottom, sheetMedia.viewPadding.bottom),
        );
        final maxSheetHeight =
            math.min(screenHeight * 0.82, screenHeight - topInset - 24.0);

        return StatefulBuilder(
          builder: (ctx, setModal) => SizedBox(
            height: maxSheetHeight,
            child: Column(
              children: [
                Expanded(
                  child: _FilterSidebar(
                    minRating: tempMinRating,
                    onRatingChanged: (r) =>
                        setModal(() => tempMinRating = r),
                    minDiscount: tempMinDiscount,
                    onDiscountChanged: (d) =>
                        setModal(() => tempMinDiscount = d),
                    selectedPriceRange: tempPriceRange,
                    onPriceRangeChanged: (r) =>
                        setModal(() => tempPriceRange = r),
                    maxDistanceKm: tempMaxDistance,
                    onDistanceChanged: (d) =>
                        setModal(() => tempMaxDistance = d),
                    filterInstant: tempInstant,
                    onInstantChanged: (v) =>
                        setModal(() => tempInstant = v),
                    filterSchedule: tempSchedule,
                    onScheduleChanged: (v) =>
                        setModal(() => tempSchedule = v),
                    vendors: vendors,
                    onClearAll: () {
                      setModal(() {
                        tempMinRating = null;
                        tempMinDiscount = null;
                        tempPriceRange = null;
                        tempMaxDistance = null;
                        tempInstant = false;
                        tempSchedule = false;
                      });
                      _clearAll();
                    },
                    isModal: true,
                  ),
                ),
                Container(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottomInset),
                  decoration: const BoxDecoration(
                    color: AppColors.surface,
                    border:
                        Border(top: BorderSide(color: AppColors.border)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            setModal(() {
                              tempMinRating = null;
                              tempMinDiscount = null;
                              tempPriceRange = null;
                              tempMaxDistance = null;
                              tempInstant = false;
                              tempSchedule = false;
                            });
                            _clearAll();
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.textPrimary,
                            side: const BorderSide(color: AppColors.border),
                            padding:
                                const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          child: Text(
                            'Clear All',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () {
                            setState(() {
                              _minRating = tempMinRating;
                              _minDiscount = tempMinDiscount;
                              _selectedPriceRange = tempPriceRange;
                              _maxDistanceKm = tempMaxDistance;
                              _filterInstant = tempInstant;
                              _filterSchedule = tempSchedule;
                            });
                            Navigator.of(sheetCtx).pop();
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            padding:
                                const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          child: Text(
                            'Apply',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── Desktop sub-header with breadcrumb and vendor count ───────────────────────

class _SubHeader extends StatelessWidget {
  const _SubHeader({
    required this.moduleLabel,
    required this.vendorCount,
  });

  final String moduleLabel;
  final int vendorCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.arrow_back_rounded,
                    color: AppColors.textPrimary, size: 20),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: Text(
                          'InstaHelp',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6),
                      child: Icon(Icons.chevron_right_rounded,
                          size: 14, color: AppColors.textHint),
                    ),
                    Text(
                      moduleLabel,
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
                if (vendorCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '$vendorCount vendor${vendorCount == 1 ? '' : 's'} available',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Mobile compact header ─────────────────────────────────────────────────────

class _MobileHeader extends StatelessWidget {
  const _MobileHeader({
    required this.moduleLabel,
    required this.vendorCount,
    required this.activeFilterCount,
    required this.onFilterTap,
  });

  final String moduleLabel;
  final int vendorCount;
  final int activeFilterCount;
  final VoidCallback onFilterTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(12, 10, 16, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            behavior: HitTestBehavior.opaque,
            child: const Padding(
              padding: EdgeInsets.all(6),
              child: Icon(Icons.arrow_back_rounded,
                  color: AppColors.textPrimary, size: 20),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Text(
                        'InstaHelp',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      child: Text(
                        '→',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: AppColors.textHint,
                        ),
                      ),
                    ),
                    Flexible(
                      child: Text(
                        moduleLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '$vendorCount vendor${vendorCount == 1 ? '' : 's'}',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: onFilterTap,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.tune_rounded,
                      color: Colors.white, size: 15),
                  const SizedBox(width: 6),
                  Text(
                    activeFilterCount > 0
                        ? 'Filter ($activeFilterCount)'
                        : 'Filter',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Filter sidebar ────────────────────────────────────────────────────────────

class _FilterSidebar extends StatelessWidget {
  const _FilterSidebar({
    required this.minRating,
    required this.onRatingChanged,
    required this.minDiscount,
    required this.onDiscountChanged,
    required this.selectedPriceRange,
    required this.onPriceRangeChanged,
    required this.maxDistanceKm,
    required this.onDistanceChanged,
    required this.filterInstant,
    required this.onInstantChanged,
    required this.filterSchedule,
    required this.onScheduleChanged,
    required this.vendors,
    required this.onClearAll,
    this.isModal = false,
  });

  final double? minRating;
  final void Function(double?) onRatingChanged;
  final int? minDiscount;
  final void Function(int?) onDiscountChanged;
  final RangeValues? selectedPriceRange;
  final void Function(RangeValues?) onPriceRangeChanged;
  final double? maxDistanceKm;
  final void Function(double?) onDistanceChanged;
  final bool filterInstant;
  final void Function(bool) onInstantChanged;
  final bool filterSchedule;
  final void Function(bool) onScheduleChanged;
  final List<InstaHelpVendorModel> vendors;
  final VoidCallback onClearAll;
  final bool isModal;

  static const _ratingOptions = [
    (4.5, '4.5 and above'),
    (4.0, '4.0 and above'),
    (3.5, '3.5 and above'),
  ];

  @override
  Widget build(BuildContext context) {
    final (pMin, pMax) =
        _InstaHelpVendorListScreenState._priceBounds(vendors);
    final hasPriceBounds = pMax > pMin;

    final maxDist =
        _InstaHelpVendorListScreenState._maxDistanceBound(vendors);
    final hasDistanceData = vendors.any((v) => v.distanceKm != null);

    final listView = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (isModal)
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

        // Header row
        Row(
          children: [
            Text(
              'Filter',
              style: GoogleFonts.poppins(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const Spacer(),
            if (!isModal)
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: onClearAll,
                  child: Text(
                    'Clear All',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        const Divider(color: AppColors.border, height: 1),

        // ── Ratings ─────────────────────────────────────────────────────
        const SizedBox(height: 14),
        const _SectionTitle('Ratings'),
        const SizedBox(height: 10),
        ..._ratingOptions.map((r) => _CheckboxOption(
              label: r.$2,
              checked: minRating == r.$1,
              onTap: () =>
                  onRatingChanged(minRating == r.$1 ? null : r.$1),
            )),

        // ── Availability ────────────────────────────────────────────────
        const SizedBox(height: 14),
        const Divider(color: AppColors.border, height: 1),
        const SizedBox(height: 14),
        const _SectionTitle('Availability'),
        const SizedBox(height: 10),
        _CheckboxOption(
          label: 'Instant Available',
          checked: filterInstant,
          onTap: () => onInstantChanged(!filterInstant),
        ),
        _CheckboxOption(
          label: 'Schedule Available',
          checked: filterSchedule,
          onTap: () => onScheduleChanged(!filterSchedule),
        ),

        // ── Discount ────────────────────────────────────────────────────
        const SizedBox(height: 14),
        const Divider(color: AppColors.border, height: 1),
        const SizedBox(height: 14),
        const _SectionTitle('Discount'),
        const SizedBox(height: 10),
        ..._kDiscounts.map((d) => _CheckboxOption(
              label: d.$2,
              checked: minDiscount == d.$1,
              onTap: () =>
                  onDiscountChanged(minDiscount == d.$1 ? null : d.$1),
            )),

        // ── Price Range ─────────────────────────────────────────────────
        const SizedBox(height: 14),
        const Divider(color: AppColors.border, height: 1),
        const SizedBox(height: 14),
        const _SectionTitle('Price Range'),
        const SizedBox(height: 10),
        if (hasPriceBounds)
          _PriceRangeSection(
            sliderMin: pMin,
            sliderMax: pMax,
            selectedRange: selectedPriceRange,
            onChanged: onPriceRangeChanged,
          )
        else
          Text(
            'Price data loading…',
            style: GoogleFonts.inter(
              fontSize: 12,
              color: AppColors.textHint,
            ),
          ),

        // ── Distance ────────────────────────────────────────────────────
        if (hasDistanceData) ...[
          const SizedBox(height: 14),
          const Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 14),
          const _SectionTitle('Distance'),
          const SizedBox(height: 10),
          _DistanceSection(
            maxBound: maxDist,
            value: maxDistanceKm,
            onChanged: onDistanceChanged,
          ),
        ],

        const SizedBox(height: 20),
      ],
    );

    if (isModal) return listView;

    return Container(
      width: 260,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      child: listView,
    );
  }
}

// ── Section title ─────────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: GoogleFonts.poppins(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
      );
}

// ── Checkbox option (multi-select) ────────────────────────────────────────────

class _CheckboxOption extends StatelessWidget {
  const _CheckboxOption({
    required this.label,
    required this.checked,
    required this.onTap,
  });
  final String label;
  final bool checked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: Checkbox(
                  value: checked,
                  onChanged: (_) => onTap(),
                  activeColor: AppColors.primary,
                  side:
                      const BorderSide(color: AppColors.border, width: 1.5),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(3)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: checked
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                    fontWeight:
                        checked ? FontWeight.w500 : FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Distance slider section ───────────────────────────────────────────────────

class _DistanceSection extends StatelessWidget {
  const _DistanceSection({
    required this.maxBound,
    required this.value,
    required this.onChanged,
  });

  final double maxBound;
  final double? value;
  final void Function(double?) onChanged;

  static const _black = Color(0xFF171717);

  @override
  Widget build(BuildContext context) {
    final current = value ?? maxBound;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '0 km',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _black,
              ),
            ),
            Text(
              '${current.round()} km',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _black,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: _black,
            inactiveTrackColor: const Color(0xFFE5E7EB),
            thumbColor: Colors.white,
            overlayColor: Colors.black.withAlpha(15),
            trackHeight: 3.5,
            thumbShape: const _BorderedThumbShape(),
          ),
          child: Slider(
            value: current.clamp(1.0, maxBound),
            min: 1.0,
            max: maxBound,
            divisions: maxBound > 1 ? (maxBound - 1).round() : 1,
            onChanged: (v) => onChanged(v < maxBound ? v : null),
          ),
        ),
        if (value != null)
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: () => onChanged(null),
              child: Text(
                'Any distance',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ── Price range section (preset chips + dual slider) ─────────────────────────

class _PriceRangeSection extends StatelessWidget {
  const _PriceRangeSection({
    required this.sliderMin,
    required this.sliderMax,
    required this.selectedRange,
    required this.onChanged,
  });

  final double sliderMin;
  final double sliderMax;
  final RangeValues? selectedRange;
  final void Function(RangeValues?) onChanged;

  static const _black = Color(0xFF171717);
  static const _presetLabels = ['All', '< ₹300', '₹300 – ₹600', '> ₹600'];

  RangeValues get _currentRange {
    if (selectedRange == null) return RangeValues(sliderMin, sliderMax);
    final s = selectedRange!.start.clamp(sliderMin, sliderMax);
    final e = selectedRange!.end.clamp(s, sliderMax);
    return RangeValues(s, e);
  }

  RangeValues _presetToRange(int idx) {
    switch (idx) {
      case 1:
        return RangeValues(sliderMin, math.min(300.0, sliderMax));
      case 2:
        return RangeValues(
          math.max(300.0, sliderMin),
          math.min(600.0, sliderMax),
        );
      case 3:
        return RangeValues(math.max(600.0, sliderMin), sliderMax);
      default:
        return RangeValues(sliderMin, sliderMax);
    }
  }

  int? get _activePreset {
    if (selectedRange == null) return 0;
    final r = _currentRange;
    if (r.start.round() <= sliderMin.round() &&
        r.end.round() >= sliderMax.round()) {
      return 0;
    }
    for (int i = 1; i <= 3; i++) {
      final pr = _presetToRange(i);
      if (r.start.round() == pr.start.round() &&
          r.end.round() == pr.end.round()) {
        return i;
      }
    }
    return null;
  }

  static String _fmt(double value) {
    final n = value.round();
    if (n >= 1000) {
      final k = n ~/ 1000;
      final rem = n % 1000;
      if (rem == 0) return '₹${k}k';
    }
    return '₹$n';
  }

  @override
  Widget build(BuildContext context) {
    final range = _currentRange;
    final activePreset = _activePreset;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: List.generate(
            _presetLabels.length,
            (i) => _PricePresetChip(
              label: _presetLabels[i],
              isSelected: activePreset == i,
              onTap: () =>
                  i == 0 ? onChanged(null) : onChanged(_presetToRange(i)),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _fmt(range.start),
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _black,
              ),
            ),
            Text(
              _fmt(range.end),
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _black,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: _black,
            inactiveTrackColor: const Color(0xFFE5E7EB),
            thumbColor: Colors.white,
            overlayColor: Colors.black.withAlpha(15),
            trackHeight: 3.5,
            rangeThumbShape: const _BorderedRangeThumbShape(),
          ),
          child: RangeSlider(
            values: range,
            min: sliderMin,
            max: sliderMax,
            onChanged: (r) => onChanged(r),
          ),
        ),
      ],
    );
  }
}

// ── Price preset chip ─────────────────────────────────────────────────────────

class _PricePresetChip extends StatelessWidget {
  const _PricePresetChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  static const _black = Color(0xFF171717);

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding:
              const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
          decoration: BoxDecoration(
            color: isSelected ? _black : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected ? _black : const Color(0xFFD1D5DB),
            ),
          ),
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: isSelected ? Colors.white : _black,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Desktop vendor grid ───────────────────────────────────────────────────────

class _VendorGrid extends StatelessWidget {
  const _VendorGrid({required this.vendors, required this.onTap});

  final List<InstaHelpVendorModel> vendors;
  final void Function(InstaHelpVendorModel) onTap;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 300,
        mainAxisExtent: 260,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: vendors.length,
      itemBuilder: (ctx, i) => _VendorCard(
        vendor: vendors[i],
        onTap: () => onTap(vendors[i]),
      ),
    );
  }
}

// ── Mobile 2-column vendor grid ───────────────────────────────────────────────

class _MobileVendorGrid extends StatelessWidget {
  const _MobileVendorGrid({required this.vendors, required this.onTap});

  final List<InstaHelpVendorModel> vendors;
  final void Function(InstaHelpVendorModel) onTap;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return GridView.builder(
      padding:
          EdgeInsets.fromLTRB(12, 12, 12, 88 + bottomInset),
      physics: const AlwaysScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        mainAxisExtent: 230,
      ),
      itemCount: vendors.length,
      itemBuilder: (ctx, i) => _VendorCard(
        vendor: vendors[i],
        onTap: () => onTap(vendors[i]),
        isMobile: true,
      ),
    );
  }
}

// ── Vendor card ───────────────────────────────────────────────────────────────

class _VendorCard extends StatefulWidget {
  const _VendorCard({
    required this.vendor,
    required this.onTap,
    this.isMobile = false,
  });

  final InstaHelpVendorModel vendor;
  final VoidCallback onTap;
  final bool isMobile;

  @override
  State<_VendorCard> createState() => _VendorCardState();
}

class _VendorCardState extends State<_VendorCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final v = widget.vendor;
    final mobile = widget.isMobile;
    final borderColor =
        _hovered ? AppColors.gold.withAlpha(140) : AppColors.border;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor, width: 1.0),
            boxShadow: [
              BoxShadow(
                color:
                    Colors.black.withAlpha(_hovered ? 15 : 6),
                blurRadius: _hovered ? 14 : 4,
                offset: Offset(0, _hovered ? 4 : 1),
              ),
            ],
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Padding(
                padding: mobile
                    ? const EdgeInsets.fromLTRB(10, 12, 10, 10)
                    : const EdgeInsets.fromLTRB(12, 18, 12, 12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _VendorAvatar(
                      imageUrl: v.profileImageUrl,
                      radius: mobile ? 28 : 36,
                    ),
                    SizedBox(height: mobile ? 7 : 9),

                    // Name + verified badge
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            v.businessName,
                            textAlign: TextAlign.center,
                            maxLines: mobile ? 1 : 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                              fontSize: mobile ? 12 : 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                              height: 1.3,
                            ),
                          ),
                        ),
                        if (v.isVerified) ...[
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.verified_rounded,
                            size: 14,
                            color: Color(0xFF0284C7),
                          ),
                        ],
                      ],
                    ),
                    SizedBox(height: mobile ? 5 : 6),

                    // Online / Offline badge
                    if (v.isOnline)
                      _StatusBadge(
                        label: 'Online',
                        dotColor: const Color(0xFF16A34A),
                        bgColor: const Color(0xFFDCFCE7),
                        textColor: const Color(0xFF16A34A),
                        mobile: mobile,
                      )
                    else if (mobile)
                      _StatusBadge(
                        label: 'Offline',
                        dotColor: const Color(0xFF6B7280),
                        bgColor: const Color(0xFFF3F4F6),
                        textColor: const Color(0xFF4B5563),
                        mobile: mobile,
                      )
                    else
                      const SizedBox(height: 20),

                    // Instant / Schedule availability pills
                    if (v.instantAvailable || v.scheduleAvailable) ...[
                      SizedBox(height: mobile ? 4 : 5),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          if (v.instantAvailable)
                            _AvailPill(
                              label: 'Instant',
                              icon: Icons.flash_on_rounded,
                              color: AppColors.goldDeep,
                              mobile: mobile,
                            ),
                          if (v.scheduleAvailable)
                            _AvailPill(
                              label: 'Scheduled',
                              icon: Icons.calendar_today_rounded,
                              color: const Color(0xFF4F6DFF),
                              mobile: mobile,
                            ),
                        ],
                      ),
                    ] else
                      SizedBox(height: mobile ? 4 : 5),

                    SizedBox(height: mobile ? 4 : 5),

                    // Rating + reviews
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.star_rounded,
                            size: 13, color: AppColors.gold),
                        const SizedBox(width: 3),
                        Text(
                          v.rating != null
                              ? v.rating!.toStringAsFixed(1)
                              : (mobile ? '0.0' : '—'),
                          style: GoogleFonts.inter(
                            fontSize: mobile ? 11.5 : 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        if (v.totalReviews > 0)
                          Flexible(
                            child: Text(
                              ' · ${v.totalReviews} review${v.totalReviews == 1 ? '' : 's'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                      ],
                    ),

                    if (v.minServicePrice != null) ...[
                      SizedBox(height: mobile ? 2 : 3),
                      Text(
                        'From ₹${v.minServicePrice!.toInt()}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Positioned(
                top: 10,
                right: 10,
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: AppColors.textHint,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Small online/offline status badge ────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({
    required this.label,
    required this.dotColor,
    required this.bgColor,
    required this.textColor,
    required this.mobile,
  });

  final String label;
  final Color dotColor;
  final Color bgColor;
  final Color textColor;
  final bool mobile;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: mobile ? 9 : 10,
        vertical: mobile ? 2.5 : 3,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration:
                BoxDecoration(shape: BoxShape.circle, color: dotColor),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: mobile ? 10.5 : 11,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Instant / Schedule availability pill ─────────────────────────────────────

class _AvailPill extends StatelessWidget {
  const _AvailPill({
    required this.label,
    required this.icon,
    required this.color,
    required this.mobile,
  });

  final String label;
  final IconData icon;
  final Color color;
  final bool mobile;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: mobile ? 6 : 7,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: mobile ? 9 : 10, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: mobile ? 9 : 10,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Vendor avatar ─────────────────────────────────────────────────────────────

class _VendorAvatar extends StatelessWidget {
  const _VendorAvatar({this.imageUrl, required this.radius});
  final String? imageUrl;
  final double radius;

  @override
  Widget build(BuildContext context) {
    if (imageUrl != null) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: AppColors.surfaceVariant,
        backgroundImage: NetworkImage(imageUrl!),
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.surfaceVariant,
      child: Icon(Icons.storefront_rounded,
          size: radius * 0.75, color: AppColors.textHint),
    );
  }
}

// ── Empty / Error states ──────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.hasFilters, required this.onClear});
  final bool hasFilters;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              hasFilters
                  ? Icons.search_off_rounded
                  : Icons.person_search_rounded,
              size: 52,
              color: AppColors.textHint,
            ),
            const SizedBox(height: 14),
            Text(
              hasFilters
                  ? 'No vendors match your filters'
                  : 'No vendors found in this area',
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            if (hasFilters) ...[
              const SizedBox(height: 6),
              Text(
                'Try adjusting your filters',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: onClear,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  minimumSize: const Size(0, 40),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 22, vertical: 10),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: Text(
                  'Clear Filters',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ] else ...[
              const SizedBox(height: 8),
              Text(
                'Try a different location.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 48, color: AppColors.textHint),
            const SizedBox(height: 12),
            Text(
              'Failed to load vendors',
              style: GoogleFonts.poppins(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                  fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Custom range slider thumb ─────────────────────────────────────────────────

class _BorderedRangeThumbShape extends RangeSliderThumbShape {
  const _BorderedRangeThumbShape();
  static const double _r = 9.0;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      Size.fromRadius(_r);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    bool isDiscrete = false,
    bool isEnabled = false,
    bool isOnTop = false,
    required SliderThemeData sliderTheme,
    TextDirection? textDirection,
    Thumb? thumb,
    bool isPressed = false,
  }) {
    final canvas = context.canvas;
    canvas.drawCircle(
      center.translate(0, 1),
      _r,
      Paint()
        ..color = Colors.black.withAlpha(30)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawCircle(center, _r, Paint()..color = Colors.white);
    canvas.drawCircle(
      center,
      _r - 0.75,
      Paint()
        ..color = const Color(0xFF171717)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }
}

// ── Custom single slider thumb ────────────────────────────────────────────────

class _BorderedThumbShape extends SliderComponentShape {
  const _BorderedThumbShape();
  static const double _r = 9.0;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      Size.fromRadius(_r);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    canvas.drawCircle(
      center.translate(0, 1),
      _r,
      Paint()
        ..color = Colors.black.withAlpha(30)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawCircle(center, _r, Paint()..color = Colors.white);
    canvas.drawCircle(
      center,
      _r - 0.75,
      Paint()
        ..color = const Color(0xFF171717)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }
}
