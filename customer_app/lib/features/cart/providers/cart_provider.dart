import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/cart_item.dart';
import '../../../features/catalog/models/catalog_node_model.dart';
import '../../../features/amc/models/amc_plan_model.dart';
import '../../../models/addon_model.dart';
import '../services/cart_sync_service.dart';

/// Composite key for merging cart items by catalog occurrence (serviceId + parentNodeId).
String _cartMergeKey(String serviceId, String? parentNodeId) =>
    '$serviceId|${parentNodeId ?? ''}';

/// Returns the first CartItem whose configuration exactly matches the given
/// parameters, or null if no match exists.
///
/// Parent scoping: when [parentNodeId] is non-null, only items whose own
/// parentNodeId matches (or is null — backward-compatible for legacy items
/// stored without parentNodeId) are considered.
CartItem? findMatchingCartItem(
  List<CartItem> items, {
  required String serviceId,
  required bool isAmc,
  String? amcPlanId,
  required Set<String> addonIds,
  required double effectiveBasePrice,
  String? parentNodeId,
}) {
  for (final item in items) {
    if (item.serviceId != serviceId) continue;
    if (item.isAmc != isAmc) continue;
    // Skip items that belong to a different known catalog occurrence.
    if (parentNodeId != null &&
        item.parentNodeId != null &&
        item.parentNodeId != parentNodeId) continue;
    if (isAmc) {
      if (item.amcPlanId == amcPlanId) return item;
    } else {
      final itemAddonIds = item.addons.map((a) => a.addonId).toSet();
      if (itemAddonIds.length != addonIds.length) continue;
      if (!itemAddonIds.containsAll(addonIds)) continue;
      final itemEffBase = item.unitPrice - totalAddonsPrice(item.addons);
      if ((itemEffBase - effectiveBasePrice).abs() > 0.01) continue;
      return item;
    }
  }
  return null;
}

class CartNotifier extends StateNotifier<List<CartItem>> {
  static const _storageKey = 'dodo_cart_v1';

  final _sync = CartSyncService();

  CartNotifier() : super([]) {
    _load();
  }

  // ── Persistence ───────────────────────────────────────────────────────────

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null) return;
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      state = decoded
          .map((e) => CartItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      // Corrupted data — start fresh
      await prefs.remove(_storageKey);
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey,
      jsonEncode(state.map((e) => e.toJson()).toList()),
    );
  }

  // ── Remote sync (login) ───────────────────────────────────────────────────

  /// Called after login. Merges Supabase cart with local:
  /// remote wins for business data (quantity, price); local wins for
  /// parentNodeId because the remote cart_items table has no such column
  /// and a null from remote must not erase the navigation context set locally.
  Future<void> loadFromRemote() async {
    final remoteItems = await _sync.fetchAll();
    if (remoteItems.isEmpty && state.isEmpty) return;

    // Key by (serviceId, parentNodeId) so shared-node occurrences stay separate.
    final merged = <String, CartItem>{
      for (final item in state)
        _cartMergeKey(item.serviceId, item.parentNodeId): item,
    };

    // Remote wins for business data; local AMC metadata is preserved because
    // CartSyncService does not store AMC fields. parentNodeId is authoritative
    // from the remote row (it now persists parent_node_id).
    for (final remote in remoteItems) {
      final key = _cartMergeKey(remote.serviceId, remote.parentNodeId);
      final local = merged[key];
      debugPrint('[DODO][CartSync][loadFromRemote] merging key=$key  '
          'local.parentNodeId=${local?.parentNodeId}  remote.parentNodeId=${remote.parentNodeId}');
      merged[key] = CartItem(
        bookingId: local?.bookingId ??
            '${remote.serviceId}_${remote.parentNodeId ?? ''}_${DateTime.now().millisecondsSinceEpoch}',
        serviceId: remote.serviceId,
        serviceName: remote.serviceName,
        imageUrl: remote.imageUrl ?? local?.imageUrl,
        unitPrice: remote.unitPrice,
        quantity: remote.quantity,
        minimumOrderAmount: remote.minimumOrderAmount ?? local?.minimumOrderAmount,
        parentNodeId: remote.parentNodeId ?? local?.parentNodeId,
        isAmc: local?.isAmc ?? false,
        amcPlanName: local?.amcPlanName,
        amcRecurrenceInterval: local?.amcRecurrenceInterval,
        amcPlanId: local?.amcPlanId,
        amcPricePerVisit: local?.amcPricePerVisit,
        amcNumVisits: local?.amcNumVisits,
        amcOriginalTotal: local?.amcOriginalTotal,
        amcDiscountType: local?.amcDiscountType,
        amcDiscountValue: local?.amcDiscountValue,
        amcDiscountAmount: local?.amcDiscountAmount,
        amcFinalPrice: local?.amcFinalPrice,
        amcPackageDuration: local?.amcPackageDuration,
        amcServiceInterval: local?.amcServiceInterval,
        amcQuantity: local?.amcQuantity ?? 1,
        amcIsRenewal: local?.amcIsRenewal ?? false,
        amcPreviousContractId: local?.amcPreviousContractId,
      );
    }

    // Local-only items: push to remote
    final remoteKeys = {
      for (final r in remoteItems) _cartMergeKey(r.serviceId, r.parentNodeId)
    };
    for (final local in state) {
      if (!remoteKeys.contains(_cartMergeKey(local.serviceId, local.parentNodeId))) {
        unawaited(_sync.upsertItem(local));
      }
    }

    state = merged.values.toList();
    await _save();
  }

  // ── Mutations ─────────────────────────────────────────────────────────────

  void addToCart(
    CatalogNodeModel service, {
    double priceAdjustment = 0.0,
    String? parentNodeId,
    AmcPlanModel? amcPlan,
    int amcQuantity = 1,
    bool amcIsRenewal = false,
    String? amcPreviousContractId,
    List<SelectedAddon> addons = const [],
  }) {
    debugPrint('[DODO][CartSync][1] addToCart() entered — serviceId=${service.id} name=${service.name} parentNodeId=$parentNodeId isAmc=${amcPlan != null}');
    final isAmc = amcPlan != null;
    final unitPrice = isAmc
        ? amcPlan.finalPrice * amcQuantity
        : (service.basePrice ?? 0.0) + priceAdjustment;

    // Merge into the existing CartItem if the configuration is identical.
    final addonIds = addons.map((a) => a.addonId).toSet();
    final effectiveBase = isAmc ? 0.0 : unitPrice - totalAddonsPrice(addons);
    final existing = findMatchingCartItem(
      state,
      serviceId: service.id,
      isAmc: isAmc,
      amcPlanId: amcPlan?.id,
      addonIds: addonIds,
      effectiveBasePrice: effectiveBase,
      parentNodeId: parentNodeId,
    );
    if (existing != null) {
      updateQuantity(existing.bookingId, existing.quantity + 1);
      return;
    }

    final bookingId = '${service.id}_${DateTime.now().millisecondsSinceEpoch}';
    final newItem = CartItem(
      bookingId: bookingId,
      serviceId: service.id,
      serviceName: service.name,
      imageUrl: service.imageUrl,
      unitPrice: unitPrice,
      quantity: 1,
      minimumOrderAmount: isAmc ? null : service.minimumOrderAmount,
      parentNodeId: parentNodeId,
      isAmc: isAmc,
      amcPlanName: amcPlan?.planName,
      amcRecurrenceInterval: amcPlan?.serviceIntervalLabel,
      amcPlanId: amcPlan?.id,
      amcPricePerVisit: amcPlan?.pricePerVisit,
      amcNumVisits: amcPlan?.numVisits,
      amcOriginalTotal: amcPlan?.originalTotal,
      amcDiscountType: amcPlan?.discountType,
      amcDiscountValue: amcPlan?.discountValue,
      amcDiscountAmount: amcPlan?.discountAmount,
      amcFinalPrice: amcPlan?.finalPrice,
      amcPackageDuration: amcPlan?.packageDuration,
      amcServiceInterval: amcPlan?.serviceInterval,
      amcQuantity: isAmc ? amcQuantity : 1,
      amcIsRenewal: amcIsRenewal,
      amcPreviousContractId: amcPreviousContractId,
      addons: addons,
    );
    state = [...state, newItem];
    _save();
    unawaited(_sync.upsertItem(newItem));
  }

  void removeFromCart(String bookingId) {
    final item = state.firstWhere((i) => i.bookingId == bookingId,
        orElse: () => throw StateError('bookingId not found: $bookingId'));
    final serviceId = item.serviceId;
    final parentNodeId = item.parentNodeId;
    state = state.where((i) => i.bookingId != bookingId).toList();
    _save();
    // Delete the remote row only when no other local item shares the same
    // catalog occurrence (serviceId + parentNodeId).
    if (!state.any((i) =>
        i.serviceId == serviceId && i.parentNodeId == parentNodeId)) {
      unawaited(_sync.deleteItem(serviceId, parentNodeId));
    }
  }

  void updateAddons(
    String bookingId,
    List<SelectedAddon> addons,
    double newUnitPrice,
  ) {
    state = [
      for (final item in state)
        if (item.bookingId == bookingId)
          item.copyWith(unitPrice: newUnitPrice, addons: addons)
        else
          item,
    ];
    _save();
    final updated = state.firstWhere((i) => i.bookingId == bookingId);
    unawaited(_sync.upsertItem(updated));
  }

  void updateQuantity(String bookingId, int quantity) {
    if (quantity <= 0) {
      removeFromCart(bookingId);
      return;
    }
    state = [
      for (final item in state)
        if (item.bookingId == bookingId)
          item.copyWith(
            quantity: quantity,
            amcQuantity: item.isAmc && item.amcIsRenewal ? quantity : null,
          )
        else item,
    ];
    _save();
    final updated = state.firstWhere((i) => i.bookingId == bookingId);
    unawaited(_sync.upsertItem(updated));
  }

  void clearCart() {
    state = [];
    _save();
    unawaited(_sync.clearAll());
  }

  /// Replaces the entire cart with a single item. Used by "Schedule Next Visit"
  /// from the AMC contract card to pre-populate checkout.
  void replaceWithSingleItem(CartItem item) {
    state = [item];
    unawaited(_save());
  }
}

final cartProvider = StateNotifierProvider<CartNotifier, List<CartItem>>(
  (_) => CartNotifier(),
);

final cartItemCountProvider = Provider<int>((ref) {
  return ref.watch(cartProvider).fold(0, (sum, item) => sum + item.quantity);
});

final cartSubtotalProvider = Provider<double>((ref) {
  return ref.watch(cartProvider).fold(0.0, (sum, item) => sum + item.totalPrice);
});
