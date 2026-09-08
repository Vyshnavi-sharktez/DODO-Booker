import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/cart_item.dart';
import '../../../features/catalog/models/catalog_node_model.dart';
import '../../../features/amc/models/amc_plan_model.dart';
import '../../../features/vendor_custom_service/models/vendor_custom_service_model.dart';
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
    if (raw != null) {
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
    // Always attempt a remote sync on startup. When the user is already
    // authenticated (e.g. returning web session), this loads any cart items
    // added from another platform. CartSyncService._customerId() returns null
    // when not logged in, so loadFromRemote() exits early with no network call.
    await loadFromRemote();
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
        addons: local?.addons ?? const [],
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
    double? unitPriceOverride,
    double? originalUnitPrice,
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
        : unitPriceOverride ?? ((service.basePrice ?? 0.0) + priceAdjustment);

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
      originalUnitPrice: isAmc ? null : originalUnitPrice,
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
    final isCustom = item.isCustomService;
    state = state.where((i) => i.bookingId != bookingId).toList();
    _save();
    // Custom service items are never synced to cart_items (no catalog_nodes FK).
    if (!isCustom &&
        !state.any((i) =>
            i.serviceId == serviceId && i.parentNodeId == parentNodeId)) {
      unawaited(_sync.deleteItem(serviceId, parentNodeId));
    }
  }

  /// Adds a vendor custom service to the cart.
  /// Custom service items use [customServiceId] at checkout and are NOT synced
  /// to the remote cart_items table (which has a catalog_nodes FK on service_id).
  void addCustomServiceToCart(VendorCustomServiceModel service) {
    // Deduplicate: one item per vendor custom service in the cart.
    if (state.any((i) => i.customServiceId == service.id)) {
      return;
    }
    final bookingId = '${service.id}_${DateTime.now().millisecondsSinceEpoch}';
    final newItem = CartItem(
      bookingId: bookingId,
      serviceId: service.id,
      serviceName: service.serviceName,
      imageUrl: service.imageUrl,
      unitPrice: service.activePrice,
      quantity: 1,
      customServiceId: service.id,
      vendorId: service.vendorId,
    );
    state = [...state, newItem];
    _save();
    // Remote sync skipped: cart_items.service_id is a FK to catalog_nodes.
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

  /// Checks all non-custom DODO cart items against the [check_node_availability]
  /// RPC. Items whose service has been paused or deactivated are removed from
  /// the cart (both local state and remote cart_items). Returns the display
  /// names of every removed service so the caller can show the appropriate UI.
  ///
  /// Custom-service items are intentionally excluded — their Active/Inactive
  /// flow is handled separately and must not be touched here.
  Future<List<String>> pruneUnavailableNativeServices() async {
    final client = Supabase.instance.client;
    final removed = <String>[];

    // ── Custom services: batch-check is_active on vendor_service_requests ────
    final customItems = state
        .where((i) => i.isCustomService && i.customServiceId != null)
        .toList();
    if (customItems.isNotEmpty) {
      try {
        final ids = customItems.map((i) => i.customServiceId!).toList();
        final rows = await client
            .from('vendor_service_requests')
            .select('id, service_name, is_active')
            .inFilter('id', ids);
        for (final row in rows as List) {
          final r = row as Map<String, dynamic>;
          if (!(r['is_active'] as bool? ?? false)) {
            final id = r['id'] as String;
            final name = r['service_name'] as String? ?? 'A service';
            // Snapshot before removal — removeFromCart mutates state.
            final toRemove = state
                .where((i) => i.isCustomService && i.customServiceId == id)
                .toList();
            for (final affected in toRemove) {
              removeFromCart(affected.bookingId);
            }
            removed.add(name);
          }
        }
      } catch (e) {
        debugPrint('[DODO][Cart] pruneUnavailableNativeServices (custom): $e');
      }
    }

    // ── DODO catalog services: check_node_availability RPC ───────────────────
    final nativeItems = state.where((i) => !i.isCustomService).toList();
    if (nativeItems.isEmpty) return removed;

    final seen = <String>{};

    for (final item in nativeItems) {
      final key = '${item.serviceId}:${item.parentNodeId}';
      if (seen.contains(key)) continue;
      seen.add(key);
      try {
        bool isUnavailable = false;

        // Primary check: walks ancestor path (and checks relationship-scoped
        // availability when parentNodeId is set).
        final result = await client.rpc('check_node_availability', params: {
          'p_node_id': item.serviceId,
          'p_parent_id': item.parentNodeId,
        });
        final status = result is Map
            ? ((result as Map<String, dynamic>)['status'] as String? ?? 'active')
            : 'active';
        if (status != 'active') {
          isUnavailable = true;
        }

        // Fallback when parentNodeId is unknown: the RPC cannot check
        // relationship-scoped availability without a parent. Explicitly query
        // catalog_node_relationships so admin's path-scoped pauses are caught.
        if (!isUnavailable && item.parentNodeId == null) {
          final relRows = await client
              .from('catalog_node_relationships')
              .select('availability_status')
              .eq('child_id', item.serviceId);
          isUnavailable = (relRows as List).any((r) {
            final s =
                (r as Map<String, dynamic>)['availability_status'] as String? ??
                    'active';
            return s != 'active';
          });
        }

        if (isUnavailable) {
          // Snapshot affected items before removal — removeFromCart mutates state.
          final toRemove = state
              .where((i) =>
                  !i.isCustomService &&
                  i.serviceId == item.serviceId &&
                  i.parentNodeId == item.parentNodeId)
              .toList();
          for (final affected in toRemove) {
            removeFromCart(affected.bookingId);
          }
          removed.add(item.serviceName);
        }
      } catch (e) {
        debugPrint('[DODO][Cart] pruneUnavailableNativeServices: $e');
      }
    }

    return removed;
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
