import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../models/service_attribute_model.dart';
import '../../vendor_custom_service/models/vendor_custom_service_model.dart';
import '../models/vcs_category_model.dart';
import '../models/vcs_vendor_model.dart';

// ── Category tiles — realtime: re-fetches RPC on any vendor_service_requests change ──

final vcsCategoriesProvider =
    StreamProvider<List<VcsCategoryModel>>((ref) {
  final client = Supabase.instance.client;
  final controller = StreamController<List<VcsCategoryModel>>();

  Future<void> fetch() async {
    try {
      final data = await client.rpc('get_vcs_categories');
      if (!controller.isClosed) {
        controller.add((data as List)
            .map((e) => VcsCategoryModel.fromMap(e as Map<String, dynamic>))
            .toList());
      }
    } catch (_) {
      if (!controller.isClosed) controller.add([]);
    }
  }

  fetch();

  final channel = client
      .channel('vcs-categories-watch')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'vendor_service_requests',
        callback: (_) => fetch(),
      )
      .subscribe();

  ref.onDispose(() {
    controller.close();
    client.removeChannel(channel);
  });

  return controller.stream;
});

// ── Vendor list for a category ────────────────────────────────────────────────

final vcsVendorsProvider = FutureProvider.family<List<VcsVendorModel>, String>(
  (ref, categoryId) async {
    final data = await Supabase.instance.client.rpc(
      'get_vcs_vendors',
      params: {'p_category_id': categoryId},
    );
    final seenIds = <String>{};
    return (data as List)
        .map((e) => VcsVendorModel.fromMap(e as Map<String, dynamic>))
        .where((v) => seenIds.add(v.id))
        .toList();
  },
);

// ── All vendors that have custom services (across all categories) ─────────────

final allVcsVendorsProvider = FutureProvider<List<VcsVendorModel>>(
  (ref) async {
    final client = Supabase.instance.client;

    // 1. Try calling get_vcs_vendors with p_category_id = null (supported when
    //    migration 20261103000010 is applied).
    try {
      final directData = await client.rpc(
        'get_vcs_vendors',
        params: {'p_category_id': null},
      );
      final directList = (directData as List)
          .map((e) => VcsVendorModel.fromMap(e as Map<String, dynamic>))
          .toList();
      if (directList.isNotEmpty) {
        return directList;
      }
    } catch (_) {
      // Fallback below if RPC requires non-null p_category_id
    }

    // 2. Fallback: aggregate vendors across all VCS categories and sum their
    //    active custom service counts.
    final catData = await client.rpc('get_vcs_categories');
    final categories = (catData as List)
        .map((e) => VcsCategoryModel.fromMap(e as Map<String, dynamic>))
        .toList();

    if (categories.isEmpty) return [];

    final perCategoryLists = await Future.wait(
      categories.map((cat) async {
        final data = await client.rpc(
          'get_vcs_vendors',
          params: {'p_category_id': cat.id},
        );
        return (data as List)
            .map((e) => VcsVendorModel.fromMap(e as Map<String, dynamic>))
            .toList();
      }),
    );

    final Map<String, VcsVendorModel> merged = {};
    for (final list in perCategoryLists) {
      for (final v in list) {
        final existing = merged[v.id];
        if (existing == null) {
          merged[v.id] = v;
        } else {
          merged[v.id] = VcsVendorModel(
            id: existing.id,
            businessName: existing.businessName,
            rating: existing.rating ?? v.rating,
            profileImageUrl: existing.profileImageUrl ?? v.profileImageUrl,
            isOnline: existing.isOnline || v.isOnline,
            serviceCount: existing.serviceCount + v.serviceCount,
            city: existing.city ?? v.city,
            totalReviews: existing.totalReviews > 0
                ? existing.totalReviews
                : v.totalReviews,
          );
        }
      }
    }

    final result = merged.values.toList()
      ..sort((a, b) {
        final rA = a.rating ?? -1;
        final rB = b.rating ?? -1;
        final cmp = rB.compareTo(rA);
        if (cmp != 0) return cmp;
        return a.businessName.toLowerCase().compareTo(
              b.businessName.toLowerCase(),
            );
      });
    return result;
  },
);

// ── Services for vendor detail ────────────────────────────────────────────────

final vendorVcsProvider = FutureProvider.family<
    List<VendorCustomServiceModel>, ({String vendorId, String? categoryId})>(
  (ref, args) async {
    final data = await Supabase.instance.client.rpc(
      'get_vendor_vcs',
      params: {
        'p_vendor_id': args.vendorId,
        if (args.categoryId != null) 'p_category_id': args.categoryId,
      },
    );
    return (data as List)
        .map((e) => VendorCustomServiceModel.fromMap(e as Map<String, dynamic>))
        .toList();
  },
);

// ── Category Filter Data (Services root categories, Discounts & Price Range) ─

class VcsServiceFilterEntry {
  const VcsServiceFilterEntry({
    required this.serviceId,
    required this.vendorId,
    this.rootCategoryName,
    required this.effectivePrice,
    this.originalPrice,
    required this.discountPercent,
  });

  final String serviceId;
  final String vendorId;
  final String? rootCategoryName;
  final double effectivePrice;
  final double? originalPrice;
  final double discountPercent;

  bool get hasDiscount =>
      originalPrice != null &&
      originalPrice! > 0 &&
      originalPrice! > effectivePrice &&
      discountPercent > 0;
}

class VcsCategoryFilterData {
  const VcsCategoryFilterData({
    required this.rootCategoriesMap,
    required this.vendorEntries,
    this.minPrice,
    this.maxPrice,
  });

  /// Map<rootCategoryName, Set<vendorId>>
  final Map<String, Set<String>> rootCategoriesMap;

  /// Map<vendorId, List<VcsServiceFilterEntry>>
  final Map<String, List<VcsServiceFilterEntry>> vendorEntries;

  /// Minimum effective service price across all vendors in this category
  final double? minPrice;

  /// Maximum effective service price across all vendors in this category
  final double? maxPrice;
}

final vcsCategoryFilterDataProvider =
    FutureProvider.family<VcsCategoryFilterData, String>(
  (ref, categoryId) async {
    final vendors = await ref.watch(vcsVendorsProvider(categoryId).future);
    if (vendors.isEmpty) {
      return const VcsCategoryFilterData(
        rootCategoriesMap: <String, Set<String>>{},
        vendorEntries: <String, List<VcsServiceFilterEntry>>{},
      );
    }

    final servicesPerVendor = await Future.wait(
      vendors.map(
        (v) => ref.watch(
          vendorVcsProvider((vendorId: v.id, categoryId: null)).future,
        ),
      ),
    );

    // Collect service IDs that have duration/variant attribute options
    final serviceIdsWithOptions = <String>{};
    for (final services in servicesPerVendor) {
      for (final s in services) {
        if (s.optionsCount > 0) {
          serviceIdsWithOptions.add(s.id);
        }
      }
    }

    final optionsByServiceId = <String, List<ServiceAttributeOptionModel>>{};
    if (serviceIdsWithOptions.isNotEmpty) {
      try {
        final attrRows = await Supabase.instance.client
            .from('service_attributes')
            .select(
              'custom_service_id, service_attribute_options(id, attribute_id, option_name, price_adjustment, discount_type, discount_value)',
            )
            .inFilter('custom_service_id', serviceIdsWithOptions.toList());
        for (final row in (attrRows as List)) {
          final map = row as Map<String, dynamic>;
          final customServiceId = map['custom_service_id']?.toString();
          if (customServiceId == null) continue;
          final rawOpts =
              map['service_attribute_options'] as List<dynamic>? ?? const [];
          for (final o in rawOpts) {
            final opt =
                ServiceAttributeOptionModel.fromJson(o as Map<String, dynamic>);
            optionsByServiceId.putIfAbsent(customServiceId, () => []).add(opt);
          }
        }
      } catch (_) {
        // Fallback to service-level fields if attribute query fails
      }
    }

    final canonicalNames = <String, String>{};
    final rootCategoriesRaw = <String, Set<String>>{};
    final vendorEntries = <String, List<VcsServiceFilterEntry>>{};
    double? minPrice;
    double? maxPrice;

    void recordPrice(double price) {
      if (price < 0 || price.isNaN || price.isInfinite) return;
      minPrice = minPrice == null ? price : math.min(minPrice!, price);
      maxPrice = maxPrice == null ? price : math.max(maxPrice!, price);
    }

    for (var i = 0; i < vendors.length; i++) {
      final vendorId = vendors[i].id;
      final services = servicesPerVendor[i];
      final entries = <VcsServiceFilterEntry>[];

      for (final s in services) {
        String? displayCat;
        final rawCat = s.categoryName?.trim();
        if (rawCat != null && rawCat.isNotEmpty) {
          final norm = rawCat.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
          displayCat = canonicalNames.putIfAbsent(norm, () => rawCat);
          rootCategoriesRaw
              .putIfAbsent(displayCat, () => <String>{})
              .add(vendorId);
        }

        final opts = optionsByServiceId[s.id];
        if (opts != null && opts.isNotEmpty) {
          for (final opt in opts) {
            final orig = opt.priceAdjustment;
            final isDisc = opt.discountType != 'none' &&
                opt.discountValue > 0 &&
                orig > 0 &&
                orig > opt.finalPrice;
            final eff = isDisc ? opt.finalPrice : orig;
            final discPct = isDisc ? ((orig - eff) / orig) * 100.0 : 0.0;
            entries.add(
              VcsServiceFilterEntry(
                serviceId: s.id,
                vendorId: vendorId,
                rootCategoryName: displayCat,
                effectivePrice: eff,
                originalPrice: isDisc ? orig : null,
                discountPercent: discPct,
              ),
            );
            recordPrice(eff);
          }
        } else {
          final eff = s.activePrice;
          final orig = s.basePrice;
          final isDisc = s.discountType != 'none' &&
              orig != null &&
              orig > 0 &&
              orig > eff;
          final discPct = isDisc ? ((orig - eff) / orig) * 100.0 : 0.0;
          entries.add(
            VcsServiceFilterEntry(
              serviceId: s.id,
              vendorId: vendorId,
              rootCategoryName: displayCat,
              effectivePrice: eff,
              originalPrice: isDisc ? orig : null,
              discountPercent: discPct,
            ),
          );
          recordPrice(eff);
        }
      }

      vendorEntries[vendorId] = entries;
    }

    final sortedKeys = rootCategoriesRaw.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    final rootCategoriesMap = <String, Set<String>>{
      for (final k in sortedKeys) k: rootCategoriesRaw[k]!,
    };

    return VcsCategoryFilterData(
      rootCategoriesMap: rootCategoriesMap,
      vendorEntries: vendorEntries,
      minPrice: minPrice?.floorToDouble(),
      maxPrice: maxPrice?.ceilToDouble(),
    );
  },
);

// ── Shared root categories per vendor for a category ("Services" filter) ──────
// Returns Map<rootCategoryName, Set<vendorId>> for sidebar filter checkboxes.

final vcsVendorServiceNamesProvider =
    FutureProvider.family<Map<String, Set<String>>, String>(
  (ref, categoryId) async {
    final filterData =
        await ref.watch(vcsCategoryFilterDataProvider(categoryId).future);
    return filterData.rootCategoriesMap;
  },
);

// ── All categories for a vendor (derived from vendorVcsProvider) ──────────────

final vendorVcsCategoryListProvider = FutureProvider.family<
    List<({String id, String name})>, String>(
  (ref, vendorId) async {
    final services = await ref
        .watch(vendorVcsProvider((vendorId: vendorId, categoryId: null)).future);
    final seen = <String>{};
    final cats = <({String id, String name})>[];
    for (final s in services) {
      if (s.vendorCategoryId != null && seen.add(s.vendorCategoryId!)) {
        cats.add((id: s.vendorCategoryId!, name: s.categoryName ?? s.vendorCategoryId!));
      }
    }
    return cats;
  },
);
