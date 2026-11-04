import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_header.dart';
import '../../cart/providers/cart_provider.dart';
import '../../profile/utils/profile_launcher.dart';
import '../models/vcs_vendor_model.dart';
import '../providers/vcs_providers.dart';

class VendorListScreen extends ConsumerStatefulWidget {
  const VendorListScreen({
    super.key,
    required this.categoryId,
    required this.categoryName,
  });

  final String categoryId;
  final String categoryName;

  @override
  ConsumerState<VendorListScreen> createState() => _VendorListScreenState();
}

class _VendorListScreenState extends ConsumerState<VendorListScreen> {
  final Set<String> _selectedServiceNames = {};
  int? _minDiscount;
  RangeValues? _selectedPriceRange;

  void _clearAll() => setState(() {
        _selectedServiceNames.clear();
        _minDiscount = null;
        _selectedPriceRange = null;
      });

  static (double, double) _sliderBounds(VcsCategoryFilterData? filterData) {
    final rawMin = filterData?.minPrice;
    final rawMax = filterData?.maxPrice;
    if (rawMin == null || rawMax == null) return (0.0, 1000.0);
    final sMin = rawMin < rawMax ? rawMin : 0.0;
    final sMax = rawMax > sMin ? rawMax : (sMin + 1000.0);
    return (sMin, sMax);
  }

  static bool _isPriceFilterActive(
    VcsCategoryFilterData? filterData,
    RangeValues? range,
  ) {
    if (range == null ||
        filterData?.minPrice == null ||
        filterData?.maxPrice == null) {
      return false;
    }
    final (sliderMin, sliderMax) = _sliderBounds(filterData);
    return range.start.round() > sliderMin.round() ||
        range.end.round() < sliderMax.round();
  }

  static RangeValues _resolvePriceRange(
    RangeValues? selected,
    double sliderMin,
    double sliderMax,
  ) {
    if (selected == null) {
      return RangeValues(sliderMin, sliderMax);
    }
    final s = selected.start.clamp(sliderMin, sliderMax);
    final e = selected.end.clamp(s, sliderMax);
    return RangeValues(s, e);
  }

  int _activeFilterCount(VcsCategoryFilterData? filterData) =>
      _selectedServiceNames.length +
      (_minDiscount != null ? 1 : 0) +
      (_isPriceFilterActive(filterData, _selectedPriceRange) ? 1 : 0);

  List<VcsVendorModel> _filtered(
    List<VcsVendorModel> vendors,
    VcsCategoryFilterData? filterData,
  ) {
    final seenVendorIds = <String>{};
    var list = vendors.where((v) => seenVendorIds.add(v.id)).toList();

    final serviceMap = filterData?.rootCategoriesMap;
    if (_selectedServiceNames.isNotEmpty && serviceMap != null) {
      final ids = <String>{};
      for (final n in _selectedServiceNames) {
        ids.addAll(serviceMap[n] ?? {});
      }
      list = list.where((v) => ids.contains(v.id)).toList();
    }

    final hasDiscountFilter = _minDiscount != null;
    final hasPriceFilter =
        _isPriceFilterActive(filterData, _selectedPriceRange);

    if ((hasDiscountFilter || hasPriceFilter) && filterData != null) {
      final (sliderMin, sliderMax) = _sliderBounds(filterData);
      final activeRange = _resolvePriceRange(
        _selectedPriceRange,
        sliderMin,
        sliderMax,
      );
      final minP = activeRange.start.round();
      final maxP = activeRange.end.round();

      list = list.where((v) {
        final entries =
            filterData.vendorEntries[v.id] ?? const <VcsServiceFilterEntry>[];
        if (entries.isEmpty) return false;

        return entries.any((e) {
          if (_selectedServiceNames.isNotEmpty &&
              (e.rootCategoryName == null ||
                  !_selectedServiceNames.contains(e.rootCategoryName))) {
            return false;
          }
          if (hasDiscountFilter) {
            if (!e.hasDiscount || (e.discountPercent + 1e-6) < _minDiscount!) {
              return false;
            }
          }
          if (hasPriceFilter) {
            final priceInt = e.effectivePrice.round();
            if (priceInt < minP || priceInt > maxP) {
              return false;
            }
          }
          return true;
        });
      }).toList();
    }

    return list;
  }

  void _onVendorTap(BuildContext context, VcsVendorModel vendor) {
    context.push(
      '/vendor-catalog/category/${widget.categoryId}/vendor/${vendor.id}',
      extra: {
        'vendorName': vendor.businessName,
        'categoryName': widget.categoryName,
        'vendor': vendor,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final vendorsAsync = ref.watch(vcsVendorsProvider(widget.categoryId));
    final filterDataAsync =
        ref.watch(vcsCategoryFilterDataProvider(widget.categoryId));
    final filterData = filterDataAsync.asData?.value;
    final activeCount = _activeFilterCount(filterData);
    final isWide = MediaQuery.sizeOf(context).width >= 768;

    // ── Desktop UI ────────────────────────────────────────────────────────────
    if (isWide) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppHeader(
          onLogoTap: () => context.go('/'),
          onProfileTap: () => openProfile(context),
        ),
        body: Column(
          children: [
            _CategorySubHeader(
              categoryName: widget.categoryName,
              vendorCount: vendorsAsync.asData?.value != null
                  ? _filtered(vendorsAsync.asData!.value, filterData).length
                  : 0,
            ),
            const Divider(height: 1, color: AppColors.border),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _FilterSidebar(
                    selectedServiceNames: _selectedServiceNames,
                    onToggleServiceName: (n) => setState(() {
                      _selectedServiceNames.contains(n)
                          ? _selectedServiceNames.remove(n)
                          : _selectedServiceNames.add(n);
                    }),
                    minDiscount: _minDiscount,
                    onDiscountChanged: (d) =>
                        setState(() => _minDiscount = d),
                    selectedPriceRange: _selectedPriceRange,
                    onPriceRangeChanged: (r) =>
                        setState(() => _selectedPriceRange = r),
                    filterData: filterData,
                    onClearAll: _clearAll,
                  ),
                  Expanded(
                    child: vendorsAsync.when(
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (e, _) => _ErrorState(message: e.toString()),
                      data: (vendors) {
                        final filtered = _filtered(vendors, filterData);
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

    // ── Mobile UI (no desktop AppHeader, compact header with top-right Filter) ─
    final totalVendors = vendorsAsync.asData?.value;
    final filteredCount =
        totalVendors != null ? _filtered(totalVendors, filterData).length : 0;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _MobileCompactHeader(
              categoryName: widget.categoryName,
              vendorCount: filteredCount,
              activeFilterCount: activeCount,
              onFilterTap: () => _openMobileFilters(context, filterData),
            ),
            const Divider(height: 1, color: AppColors.border),
            Expanded(
              child: vendorsAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => _ErrorState(message: e.toString()),
                data: (vendors) {
                  final filtered = _filtered(vendors, filterData);
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
      BuildContext context, VcsCategoryFilterData? filterData) {
    final Set<String> tempSelectedServices =
        Set<String>.from(_selectedServiceNames);
    int? tempMinDiscount = _minDiscount;
    RangeValues? tempPriceRange = _selectedPriceRange;
    final parentMedia = MediaQuery.of(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => Consumer(
        builder: (consumerCtx, sheetRef, _) {
          final hasCartBar = sheetRef.watch(cartItemCountProvider) > 0;
          final sheetMedia = MediaQuery.of(sheetCtx);
          final screenHeight = sheetMedia.size.height;
          final topInset =
              math.max(parentMedia.padding.top, sheetMedia.padding.top);
          final bottomInset = math.max(
            math.max(parentMedia.padding.bottom, parentMedia.viewPadding.bottom),
            math.max(sheetMedia.padding.bottom, sheetMedia.viewPadding.bottom),
          );
          final cartBarClearance = hasCartBar ? 66.0 : 0.0;
          final maxSheetHeight = math.min(
            screenHeight * 0.78,
            screenHeight - topInset - 24.0,
          );

          return StatefulBuilder(
            builder: (ctx, setModal) => SizedBox(
              height: maxSheetHeight,
              child: Column(
                children: [
                  Expanded(
                    child: _FilterSidebar(
                      selectedServiceNames: tempSelectedServices,
                      onToggleServiceName: (n) => setModal(() {
                        tempSelectedServices.contains(n)
                            ? tempSelectedServices.remove(n)
                            : tempSelectedServices.add(n);
                      }),
                      minDiscount: tempMinDiscount,
                      onDiscountChanged: (d) =>
                          setModal(() => tempMinDiscount = d),
                      selectedPriceRange: tempPriceRange,
                      onPriceRangeChanged: (r) =>
                          setModal(() => tempPriceRange = r),
                      filterData: filterData,
                      onClearAll: () {
                        setModal(() {
                          tempSelectedServices.clear();
                          tempMinDiscount = null;
                          tempPriceRange = null;
                        });
                        _clearAll();
                      },
                      isModal: true,
                    ),
                  ),
                  Container(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      12,
                      16,
                      16 + bottomInset + cartBarClearance,
                    ),
                    decoration: const BoxDecoration(
                      color: AppColors.surface,
                      border: Border(top: BorderSide(color: AppColors.border)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              setModal(() {
                                tempSelectedServices.clear();
                                tempMinDiscount = null;
                                tempPriceRange = null;
                              });
                              _clearAll();
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.textPrimary,
                              side: const BorderSide(color: AppColors.border),
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
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
                                _selectedServiceNames
                                  ..clear()
                                  ..addAll(tempSelectedServices);
                                _minDiscount = tempMinDiscount;
                                _selectedPriceRange = tempPriceRange;
                              });
                              Navigator.of(sheetCtx).pop();
                            },
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
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
      ),
    );
  }
}

// ── Mobile compact page header (Back arrow + Breadcrumb + Vendor count) ──────

class _MobileCompactHeader extends StatelessWidget {
  const _MobileCompactHeader({
    required this.categoryName,
    required this.vendorCount,
    required this.activeFilterCount,
    required this.onFilterTap,
  });

  final String categoryName;
  final int vendorCount;
  final int activeFilterCount;
  final VoidCallback onFilterTap;

  void _handleBack(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(12, 10, 16, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: () => _handleBack(context),
            behavior: HitTestBehavior.opaque,
            child: const Padding(
              padding: EdgeInsets.all(6),
              child: Icon(
                Icons.arrow_back_rounded,
                color: AppColors.textPrimary,
                size: 20,
              ),
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
                      onTap: () => _handleBack(context),
                      child: Text(
                        'Vendor Catalog',
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
                        categoryName,
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
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 7,
              ),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.tune_rounded,
                    color: Colors.white,
                    size: 15,
                  ),
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

// ── Mobile 2-column vendor grid (compact desktop-style vendor cards) ─────────

class _MobileVendorGrid extends StatelessWidget {
  const _MobileVendorGrid({
    required this.vendors,
    required this.onTap,
  });

  final List<VcsVendorModel> vendors;
  final void Function(VcsVendorModel) onTap;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return GridView.builder(
      padding: EdgeInsets.fromLTRB(12, 12, 12, 88 + bottomInset),
      physics: const AlwaysScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        mainAxisExtent: 210,
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

// ── Desktop Category sub-header with back navigation and breadcrumbs ─────────

class _CategorySubHeader extends StatelessWidget {
  const _CategorySubHeader({
    required this.categoryName,
    required this.vendorCount,
  });

  final String categoryName;
  final int vendorCount;

  void _handleBack(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/');
    }
  }

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
              onTap: () => _handleBack(context),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(
                  Icons.arrow_back_rounded,
                  color: AppColors.textPrimary,
                  size: 20,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Breadcrumb trail: Vendor Catalog > Category Name
                Row(
                  children: [
                    MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () => _handleBack(context),
                        child: Text(
                          'Vendor Catalog',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6),
                      child: Icon(
                        Icons.chevron_right_rounded,
                        size: 14,
                        color: AppColors.textHint,
                      ),
                    ),
                    Flexible(
                      child: Text(
                        categoryName,
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

// ── Filter sidebar ────────────────────────────────────────────────────────────

class _FilterSidebar extends StatelessWidget {
  const _FilterSidebar({
    required this.selectedServiceNames,
    required this.onToggleServiceName,
    required this.minDiscount,
    required this.onDiscountChanged,
    required this.selectedPriceRange,
    required this.onPriceRangeChanged,
    required this.filterData,
    required this.onClearAll,
    this.isModal = false,
  });

  final Set<String> selectedServiceNames;
  final void Function(String) onToggleServiceName;
  final int? minDiscount;
  final void Function(int?) onDiscountChanged;
  final RangeValues? selectedPriceRange;
  final void Function(RangeValues) onPriceRangeChanged;
  final VcsCategoryFilterData? filterData;
  final VoidCallback onClearAll;
  final bool isModal;

  static const _discounts = [
    (10, '10% and above'),
    (20, '20% and above'),
    (30, '30% and above'),
    (40, '40% and above'),
  ];

  static String _formatCurrency(double value) {
    final n = value.round();
    final s = n.toString();
    if (s.length <= 3) return '₹$s';
    final last3 = s.substring(s.length - 3);
    var rest = s.substring(0, s.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    return '₹${parts.join(',')},$last3';
  }

  @override
  Widget build(BuildContext context) {
    final serviceNames = filterData?.rootCategoriesMap.keys.toList() ?? [];
    final rawMin = filterData?.minPrice;
    final rawMax = filterData?.maxPrice;
    final hasPriceBounds = rawMin != null && rawMax != null;
    final (sliderMin, sliderMax) =
        _VendorListScreenState._sliderBounds(filterData);
    final RangeValues currentRange = hasPriceBounds
        ? _VendorListScreenState._resolvePriceRange(
            selectedPriceRange,
            sliderMin,
            sliderMax,
          )
        : const RangeValues(0, 1000);

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

        // ── A. Services ───────────────────────────────────────────────────────
        const SizedBox(height: 14),
        const _SectionTitle('Services'),
        const SizedBox(height: 10),
        if (serviceNames.isNotEmpty)
          ...serviceNames.map((n) => _CheckboxOption(
                label: n,
                checked: selectedServiceNames.contains(n),
                onTap: () => onToggleServiceName(n),
              )),

        // ── B. Discount ───────────────────────────────────────────────────────
        const SizedBox(height: 14),
        const Divider(color: AppColors.border, height: 1),
        const SizedBox(height: 14),
        const _SectionTitle('Discount'),
        const SizedBox(height: 10),
        ..._discounts.map((d) => _CheckboxOption(
              label: d.$2,
              checked: minDiscount == d.$1,
              onTap: () =>
                  onDiscountChanged(minDiscount == d.$1 ? null : d.$1),
            )),

        // ── C. Price Range ────────────────────────────────────────────────────
        const SizedBox(height: 14),
        const Divider(color: AppColors.border, height: 1),
        const SizedBox(height: 14),
        const _SectionTitle('Price Range'),
        const SizedBox(height: 8),
        if (hasPriceBounds) ...[
          Text(
            '${_formatCurrency(currentRange.start)} – ${_formatCurrency(currentRange.end)}',
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: AppColors.primary,
              inactiveTrackColor: AppColors.border,
              thumbColor: AppColors.primary,
              overlayColor: AppColors.primary.withAlpha(24),
              trackHeight: 3.5,
              rangeThumbShape: const RoundRangeSliderThumbShape(
                enabledThumbRadius: 8,
              ),
            ),
            child: RangeSlider(
              values: currentRange,
              min: sliderMin,
              max: sliderMax,
              onChanged: onPriceRangeChanged,
            ),
          ),
        ],
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
                  side: const BorderSide(color: AppColors.border, width: 1.5),
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
                    fontWeight: checked ? FontWeight.w500 : FontWeight.w400,
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

// ── Desktop Vendor grid ───────────────────────────────────────────────────────

class _VendorGrid extends StatelessWidget {
  const _VendorGrid({
    required this.vendors,
    required this.onTap,
  });

  final List<VcsVendorModel> vendors;
  final void Function(VcsVendorModel) onTap;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 300,
        mainAxisExtent: 230,
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

// ── Vendor card (shared by desktop & mobile, scaled proportionally on mobile) ─

class _VendorCard extends StatefulWidget {
  const _VendorCard({
    required this.vendor,
    required this.onTap,
    this.isMobile = false,
  });
  final VcsVendorModel vendor;
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
                color: Colors.black.withAlpha(_hovered ? 15 : 6),
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
                    ? const EdgeInsets.fromLTRB(10, 14, 10, 10)
                    : const EdgeInsets.fromLTRB(12, 20, 12, 12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _VendorAvatar(
                      imageUrl: v.profileImageUrl,
                      radius: mobile ? 30 : 38,
                    ),
                    SizedBox(height: mobile ? 8 : 10),
                    Text(
                      v.businessName,
                      textAlign: TextAlign.center,
                      maxLines: mobile ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontSize: mobile ? 12.5 : 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                        height: 1.3,
                      ),
                    ),
                    SizedBox(height: mobile ? 5 : 6),
                    if (v.isOnline)
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: mobile ? 9 : 10,
                          vertical: mobile ? 2.5 : 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDCFCE7),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0xFF16A34A),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Online',
                              style: GoogleFonts.inter(
                                fontSize: mobile ? 10.5 : 11,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF16A34A),
                              ),
                            ),
                          ],
                        ),
                      )
                    else if (mobile)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 2.5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3F4F6),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0xFF6B7280),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Offline',
                              style: GoogleFonts.inter(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF4B5563),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      const SizedBox(height: 20),
                    SizedBox(height: mobile ? 5 : 6),
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
                    SizedBox(height: mobile ? 3 : 4),
                    Text(
                      '${v.serviceCount} service${v.serviceCount == 1 ? '' : 's'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                          fontSize: 11, color: AppColors.textSecondary),
                    ),
                    if (v.minServicePrice != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'From ₹${v.minServicePrice!.toInt()}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                            fontSize: 11, color: AppColors.textSecondary),
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
              hasFilters ? Icons.search_off_rounded : Icons.storefront_outlined,
              size: 52,
              color: AppColors.textHint,
            ),
            const SizedBox(height: 14),
            Text(
              hasFilters ? 'No vendors match your filters' : 'No vendors found',
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            if (hasFilters) ...[
              const SizedBox(height: 6),
              Text(
                'Try adjusting your filters',
                style: GoogleFonts.inter(
                    fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: onClear,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  minimumSize: const Size(0, 40),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
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
