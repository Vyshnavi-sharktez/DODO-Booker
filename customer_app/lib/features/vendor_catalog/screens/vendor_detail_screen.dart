import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_header.dart';
import '../../cart/providers/cart_provider.dart';
import '../../category/services/category_providers.dart';
import '../../profile/utils/profile_launcher.dart';
import '../../vendor_custom_service/models/vendor_custom_service_model.dart';
import '../../vendor_custom_service/widgets/vendor_custom_service_sheet.dart';
import '../models/vcs_vendor_model.dart';
import '../providers/vcs_providers.dart';

class VendorDetailScreen extends ConsumerStatefulWidget {
  const VendorDetailScreen({
    super.key,
    required this.vendorId,
    this.initialCategoryId,
    this.vendorName,
    this.categoryName,
    this.initialVendor,
  });

  final String vendorId;
  final String? initialCategoryId;
  final String? vendorName;
  final String? categoryName;
  final VcsVendorModel? initialVendor;

  @override
  ConsumerState<VendorDetailScreen> createState() => _VendorDetailScreenState();
}

class _VendorDetailScreenState extends ConsumerState<VendorDetailScreen> {
  final Set<String> _selectedCategories = {};
  String? _selectedServiceChip; // null = "All"

  void _clearAll() => setState(() {
        _selectedCategories.clear();
        _selectedServiceChip = null;
      });

  int get _activeFilterCount =>
      _selectedCategories.length + (_selectedServiceChip != null ? 1 : 0);

  static String _normCat(String s) =>
      s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  VcsVendorModel? _findVendor(List<VcsVendorModel>? vendors) {
    if (vendors == null) return null;
    for (final v in vendors) {
      if (v.id == widget.vendorId) return v;
    }
    return null;
  }

  /// Extracts distinct root categories offered by this vendor from their actual services.
  List<String> _extractVendorCategories(
      List<VendorCustomServiceModel> services) {
    final seenNormalized = <String>{};
    final result = <String>[];
    for (final s in services) {
      final cat = s.categoryName?.trim();
      if (cat != null && cat.isNotEmpty && seenNormalized.add(_normCat(cat))) {
        result.add(cat);
      }
    }
    return result;
  }

  /// Extracts distinct individual service/subcategory names offered by this vendor.
  List<String> _extractVendorServiceNames(
      List<VendorCustomServiceModel> services) {
    final seenNormalized = <String>{};
    final result = <String>[];
    for (final s in services) {
      final name = s.serviceName.trim();
      if (name.isNotEmpty && seenNormalized.add(_normCat(name))) {
        result.add(name);
      }
    }
    return result;
  }

  /// Filters the vendor's services according to the active category & service chip selections.
  List<VendorCustomServiceModel> _filterAndSortServices(
      List<VendorCustomServiceModel> services) {
    var list = services.toList();

    if (_selectedCategories.isNotEmpty) {
      final selectedNorms = _selectedCategories.map(_normCat).toSet();
      list = list
          .where((s) =>
              s.categoryName != null &&
              selectedNorms.contains(_normCat(s.categoryName!)))
          .toList();
    }

    if (_selectedServiceChip != null) {
      final chipNorm = _normCat(_selectedServiceChip!);
      list = list.where((s) => _normCat(s.serviceName) == chipNorm).toList();
    }

    return list;
  }

  void _handleBackToCategory(BuildContext context, String? resolvedCategoryName) {
    if (context.canPop()) {
      context.pop();
    } else if (widget.initialCategoryId != null) {
      context.go(
        '/vendor-catalog/category/${widget.initialCategoryId}',
        extra: resolvedCategoryName ?? 'Vendors',
      );
    } else {
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    final servicesAsync = ref.watch(vendorVcsProvider(
      (vendorId: widget.vendorId, categoryId: null),
    ));

    final categoryVendors = widget.initialCategoryId != null
        ? ref.watch(vcsVendorsProvider(widget.initialCategoryId!)).asData?.value
        : null;
    final allVendors = ref.watch(allVcsVendorsProvider).asData?.value;

    final VcsVendorModel? vendorProfile = widget.initialVendor ??
        _findVendor(categoryVendors) ??
        _findVendor(allVendors);

    final allServices =
        servicesAsync.asData?.value ?? const <VendorCustomServiceModel>[];

    final displayName = vendorProfile?.businessName ??
        widget.vendorName ??
        (allServices.isNotEmpty ? allServices.first.vendorName : 'Vendor');

    final resolvedCategoryName = widget.categoryName ??
        (widget.initialCategoryId != null
            ? allServices
                .where((s) => s.vendorCategoryId == widget.initialCategoryId)
                .map((s) => s.categoryName)
                .firstOrNull
            : null) ??
        (allServices.isNotEmpty ? allServices.first.categoryName : null);

    final vendorCategories = _extractVendorCategories(allServices);
    final vendorServiceNames = _extractVendorServiceNames(allServices);
    final isWide = MediaQuery.sizeOf(context).width >= 768;
    final horizontalPad = isWide ? 20.0 : 16.0;

    final pageBody = Column(
      children: [
        // Top sub-header with back button & breadcrumb navigation
        _VendorDetailSubHeader(
          categoryName: resolvedCategoryName,
          vendorName: displayName,
          serviceCount: allServices.length,
          onBack: () => _handleBackToCategory(context, resolvedCategoryName),
          onHomeTap: () => context.go('/'),
          onCategoryTap: () =>
              _handleBackToCategory(context, resolvedCategoryName),
        ),
        const Divider(height: 1, color: AppColors.border),
        // Main body: Persistent left filter sidebar + right vendor services grid
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isWide)
                _VendorDetailFilterSidebar(
                  vendorCategories: vendorCategories,
                  selectedCategories: _selectedCategories,
                  onToggleCategory: (c) => setState(() {
                    _selectedCategories.contains(c)
                        ? _selectedCategories.remove(c)
                        : _selectedCategories.add(c);
                  }),
                  onClearAll: _clearAll,
                ),
              Expanded(
                child: servicesAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.error_outline_rounded,
                              size: 48, color: AppColors.textHint),
                          const SizedBox(height: 12),
                          Text(
                            'Failed to load services',
                            style: GoogleFonts.poppins(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  data: (services) {
                    final filteredServices = _filterAndSortServices(services);
                    return CustomScrollView(
                      slivers: [
                        // Vendor profile header card
                        SliverToBoxAdapter(
                          child: _VendorProfileCard(
                            vendor: vendorProfile,
                            displayName: displayName,
                            serviceCount: services.length,
                          ),
                        ),
                        // Horizontal scrollable service/subcategory chips above Services Offered
                        if (vendorServiceNames.isNotEmpty)
                          SliverToBoxAdapter(
                            child: _VendorServiceChipsBar(
                              serviceNames: vendorServiceNames,
                              selectedServiceName: _selectedServiceChip,
                              horizontalPadding: horizontalPad,
                              onSelectAll: () => setState(() {
                                _selectedServiceChip = null;
                              }),
                              onSelectService: (srv) => setState(() {
                                _selectedServiceChip = srv;
                              }),
                            ),
                          ),
                        // Services section header
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                                horizontalPad, 4, horizontalPad, 14),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: Text(
                                    'Services Offered (${filteredServices.length})',
                                    style: GoogleFonts.poppins(
                                      fontSize: isWide ? 18 : 16,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                ),
                                if (isWide && _activeFilterCount > 0)
                                  MouseRegion(
                                    cursor: SystemMouseCursors.click,
                                    child: GestureDetector(
                                      onTap: _clearAll,
                                      child: Text(
                                        'Reset Filters ($_activeFilterCount)',
                                        style: GoogleFonts.inter(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.textPrimary,
                                        ),
                                      ),
                                    ),
                                  ),
                                if (!isWide)
                                  GestureDetector(
                                    onTap: () => _openMobileFilters(
                                      context,
                                      vendorCategories: vendorCategories,
                                    ),
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
                                            _selectedCategories.isNotEmpty
                                                ? 'Filter (${_selectedCategories.length})'
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
                          ),
                        ),
                        // Responsive services grid
                        if (filteredServices.isNotEmpty)
                          SliverPadding(
                            padding: EdgeInsets.fromLTRB(
                              horizontalPad,
                              0,
                              horizontalPad,
                              isWide ? 40 : 88,
                            ),
                            sliver: SliverGrid(
                              delegate: SliverChildBuilderDelegate(
                                (ctx, i) =>
                                    _ServiceCard(service: filteredServices[i]),
                                childCount: filteredServices.length,
                              ),
                              gridDelegate: isWide
                                  ? const SliverGridDelegateWithMaxCrossAxisExtent(
                                      maxCrossAxisExtent: 260,
                                      mainAxisExtent: 215,
                                      crossAxisSpacing: 14,
                                      mainAxisSpacing: 14,
                                    )
                                  : const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 2,
                                      mainAxisExtent: 215,
                                      crossAxisSpacing: 14,
                                      mainAxisSpacing: 14,
                                    ),
                            ),
                          )
                        else
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.all(40),
                              child: Center(
                                child: Column(
                                  children: [
                                    Icon(
                                      _activeFilterCount > 0
                                          ? Icons.search_off_rounded
                                          : Icons.home_repair_service_rounded,
                                      size: 48,
                                      color: AppColors.textHint,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      _activeFilterCount > 0
                                          ? 'No services match your selected filters'
                                          : 'No services available',
                                      style: GoogleFonts.poppins(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                    if (_activeFilterCount > 0) ...[
                                      const SizedBox(height: 6),
                                      Text(
                                        'Try clearing or adjusting your filter selection',
                                        style: GoogleFonts.inter(
                                          fontSize: 13,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                      const SizedBox(height: 18),
                                      FilledButton(
                                        onPressed: _clearAll,
                                        style: FilledButton.styleFrom(
                                          backgroundColor: AppColors.primary,
                                          minimumSize: const Size(0, 40),
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 22, vertical: 10),
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(10),
                                          ),
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
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: isWide
          ? AppHeader(
              onLogoTap: () => context.go('/'),
              onProfileTap: () => openProfile(context),
            )
          : null,
      body: isWide ? pageBody : SafeArea(bottom: false, child: pageBody),
    );
  }

  void _openMobileFilters(
    BuildContext context, {
    required List<String> vendorCategories,
  }) {
    final Set<String> tempSelectedCategories =
        Set<String>.from(_selectedCategories);
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
                    child: _VendorDetailFilterSidebar(
                      vendorCategories: vendorCategories,
                      selectedCategories: tempSelectedCategories,
                      onToggleCategory: (c) {
                        setModal(() {
                          tempSelectedCategories.contains(c)
                              ? tempSelectedCategories.remove(c)
                              : tempSelectedCategories.add(c);
                        });
                      },
                      onClearAll: () {
                        setModal(() {
                          tempSelectedCategories.clear();
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
                                tempSelectedCategories.clear();
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
                                _selectedCategories
                                  ..clear()
                                  ..addAll(tempSelectedCategories);
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

// ── Sub-header with Back Navigation & Breadcrumbs ─────────────────────────────

class _VendorDetailSubHeader extends StatelessWidget {
  const _VendorDetailSubHeader({
    this.categoryName,
    required this.vendorName,
    required this.serviceCount,
    required this.onBack,
    required this.onHomeTap,
    required this.onCategoryTap,
  });

  final String? categoryName;
  final String vendorName;
  final int serviceCount;
  final VoidCallback onBack;
  final VoidCallback onHomeTap;
  final VoidCallback onCategoryTap;

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
              onTap: onBack,
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
                Row(
                  children: [
                    MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: onHomeTap,
                        child: Text(
                          'Vendor Catalog',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                    if (categoryName != null && categoryName!.isNotEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6),
                        child: Icon(
                          Icons.chevron_right_rounded,
                          size: 14,
                          color: AppColors.textHint,
                        ),
                      ),
                      Flexible(
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            onTap: onCategoryTap,
                            child: Text(
                              categoryName!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
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
                        vendorName,
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
                if (serviceCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '$serviceCount service${serviceCount == 1 ? '' : 's'} offered',
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

// ── Left Filter Sidebar for Vendor Detail Page ────────────────────────────────

class _VendorDetailFilterSidebar extends StatelessWidget {
  const _VendorDetailFilterSidebar({
    required this.vendorCategories,
    required this.selectedCategories,
    required this.onToggleCategory,
    required this.onClearAll,
    this.isModal = false,
  });

  final List<String> vendorCategories;
  final Set<String> selectedCategories;
  final void Function(String) onToggleCategory;
  final VoidCallback onClearAll;
  final bool isModal;

  @override
  Widget build(BuildContext context) {
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
        const SizedBox(height: 14),
        const _SectionTitle('Services'),
        const SizedBox(height: 10),
        ...vendorCategories.map((c) => _CheckboxOption(
              label: c,
              checked: selectedCategories.contains(c),
              onTap: () => onToggleCategory(c),
            )),
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

// ── Horizontal Scrollable Vendor Service Chips Bar ────────────────────────────

class _VendorServiceChipsBar extends StatelessWidget {
  const _VendorServiceChipsBar({
    required this.serviceNames,
    required this.selectedServiceName,
    required this.onSelectAll,
    required this.onSelectService,
    this.horizontalPadding = 20.0,
  });

  final List<String> serviceNames;
  final String? selectedServiceName;
  final VoidCallback onSelectAll;
  final void Function(String) onSelectService;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    final isAllSelected = selectedServiceName == null;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.fromLTRB(horizontalPadding, 0, horizontalPadding, 14),
      child: Row(
        children: [
          _CategoryChip(
            label: 'All',
            selected: isAllSelected,
            onTap: onSelectAll,
          ),
          ...serviceNames.map(
            (srv) => Padding(
              padding: const EdgeInsets.only(left: 10),
              child: _CategoryChip(
                label: srv,
                selected: selectedServiceName == srv,
                onTap: () => onSelectService(srv),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
            ),
          ),
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? Colors.white : AppColors.textPrimary,
            ),
          ),
        ),
      ),
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

// ── Vendor profile card ───────────────────────────────────────────────────────

class _VendorProfileCard extends StatelessWidget {
  const _VendorProfileCard({
    required this.vendor,
    required this.displayName,
    required this.serviceCount,
  });

  final VcsVendorModel? vendor;
  final String displayName;
  final int serviceCount;

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 768;
    return Container(
      margin: isWide
          ? const EdgeInsets.all(20)
          : const EdgeInsets.fromLTRB(16, 14, 16, 14),
      padding: isWide ? const EdgeInsets.all(20) : const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
              color: Color(0x08000000), blurRadius: 8, offset: Offset(0, 2))
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _Avatar(
            imageUrl: vendor?.profileImageUrl,
            radius: isWide ? 42 : 30,
          ),
          SizedBox(width: isWide ? 20 : 14),
          Expanded(
            child: _ProfileDetails(
              vendor: vendor,
              displayName: displayName,
              serviceCount: serviceCount,
            ),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({this.imageUrl, this.radius = 42});
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
      child: Icon(
        Icons.storefront_rounded,
        size: radius * 0.8,
        color: AppColors.textHint,
      ),
    );
  }
}

class _ProfileDetails extends StatelessWidget {
  const _ProfileDetails({
    required this.vendor,
    required this.displayName,
    required this.serviceCount,
    this.centered = false,
  });

  final VcsVendorModel? vendor;
  final String displayName;
  final int serviceCount;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final align =
        centered ? CrossAxisAlignment.center : CrossAxisAlignment.start;
    final textAlign = centered ? TextAlign.center : TextAlign.start;

    return Column(
      crossAxisAlignment: align,
      children: [
        Text(
          displayName,
          textAlign: textAlign,
          style: GoogleFonts.poppins(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 6,
          children: [
            if (vendor?.isOnline == true)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFF16A34A),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'Online',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF16A34A),
                      ),
                    ),
                  ],
                ),
              ),
            if (vendor?.rating != null)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.star_rounded,
                      size: 16, color: AppColors.gold),
                  const SizedBox(width: 4),
                  Text(
                    vendor!.rating!.toStringAsFixed(1),
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (vendor!.totalReviews > 0)
                    Text(
                      ' (${vendor!.totalReviews} review${vendor!.totalReviews == 1 ? '' : 's'})',
                      style: GoogleFonts.inter(
                          fontSize: 13, color: AppColors.textSecondary),
                    ),
                ],
              ),
            _StatChip(
              icon: Icons.design_services_rounded,
              label: '$serviceCount service${serviceCount == 1 ? '' : 's'}',
            ),
            if (vendor?.city != null)
              _StatChip(
                icon: Icons.location_on_rounded,
                label: vendor!.city!,
              ),
          ],
        ),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.textSecondary),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.inter(
                fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      );
}

// ── Service card ──────────────────────────────────────────────────────────────

class _ServiceCard extends ConsumerStatefulWidget {
  const _ServiceCard({required this.service});
  final VendorCustomServiceModel service;

  @override
  ConsumerState<_ServiceCard> createState() => _ServiceCardState();
}

class _ServiceCardState extends ConsumerState<_ServiceCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.service;
    final attrs =
        ref.watch(serviceAttributesProvider(s.id)).valueOrNull ?? const [];
    final attrEntries = attrs.where((a) => a.options.isNotEmpty).toList();
    final cheapestOpt = attrEntries.isNotEmpty
        ? attrEntries
            .map((a) => a.options.first)
            .reduce((a, b) => a.finalPrice <= b.finalPrice ? a : b)
        : null;

    final double displayPrice =
        cheapestOpt != null ? cheapestOpt.finalPrice : s.activePrice;
    final double? originalPrice = cheapestOpt != null
        ? (cheapestOpt.hasDiscount &&
                cheapestOpt.priceAdjustment > cheapestOpt.finalPrice
            ? cheapestOpt.priceAdjustment
            : null)
        : (s.basePrice != null && s.basePrice! > s.activePrice
            ? s.basePrice
            : null);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () => VendorCustomServiceSheet.show(context, s),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color:
                  _hovered ? AppColors.gold.withAlpha(140) : AppColors.border,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(_hovered ? 15 : 5),
                blurRadius: _hovered ? 12 : 4,
                offset: Offset(0, _hovered ? 4 : 1),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: s.imageUrl != null
                      ? Image.network(
                          s.imageUrl!,
                          fit: BoxFit.cover,
                          loadingBuilder: (_, child, p) => p == null
                              ? child
                              : const ColoredBox(color: Color(0xFFF1ECE1)),
                          errorBuilder: (_, __, ___) =>
                              const _ServicePlaceholder(),
                        )
                      : const _ServicePlaceholder(),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.serviceName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      if (s.categoryName != null &&
                          s.categoryName!.trim().isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          s.categoryName!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            '₹${displayPrice.toInt()}',
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                              height: 1.2,
                            ),
                          ),
                          if (originalPrice != null) ...[
                            const SizedBox(width: 5),
                            Text(
                              '₹${originalPrice.toInt()}',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: AppColors.textHint,
                                decoration: TextDecoration.lineThrough,
                                decorationColor: AppColors.textHint,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
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

class _ServicePlaceholder extends StatelessWidget {
  const _ServicePlaceholder();

  @override
  Widget build(BuildContext context) => Container(
        color: AppColors.surfaceVariant,
        alignment: Alignment.center,
        child: const Icon(Icons.home_repair_service_rounded,
            size: 32, color: AppColors.textHint),
      );
}
