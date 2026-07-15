import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/cart_item.dart';
import '../../../features/catalog/models/catalog_node_model.dart';
import '../services/cart_sync_service.dart';

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

    final merged = <String, CartItem>{
      for (final item in state) item.serviceId: item,
    };

    // Remote wins for business data; local parentNodeId is preserved because
    // CartSyncService never stores or returns it.
    for (final remote in remoteItems) {
      final local = merged[remote.serviceId];
      debugPrint('[DODO][CartSync][loadFromRemote] merging serviceId=${remote.serviceId}  '
          'local.parentNodeId=${local?.parentNodeId}  remote.parentNodeId=${remote.parentNodeId}');
      merged[remote.serviceId] = CartItem(
        serviceId: remote.serviceId,
        serviceName: remote.serviceName,
        imageUrl: remote.imageUrl ?? local?.imageUrl,
        unitPrice: remote.unitPrice,
        quantity: remote.quantity,
        minimumOrderAmount: remote.minimumOrderAmount ?? local?.minimumOrderAmount,
        parentNodeId: local?.parentNodeId ?? remote.parentNodeId,
      );
    }

    // Local-only items: push to remote
    final remoteIds = {for (final r in remoteItems) r.serviceId};
    for (final local in state) {
      if (!remoteIds.contains(local.serviceId)) {
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
  }) {
    debugPrint('[DODO][CartSync][1] addToCart() entered — serviceId=${service.id} name=${service.name} parentNodeId=$parentNodeId');
    final idx = state.indexWhere((item) => item.serviceId == service.id);
    if (idx >= 0) {
      // Also update parentNodeId so the scoped-config path is refreshed when
      // the customer re-adds the same service through a different catalog node.
      debugPrint('[DODO][CartSync][1a] existing item found at idx=$idx  '
          'old parentNodeId=${state[idx].parentNodeId}  new parentNodeId=$parentNodeId');
      state = [
        for (int i = 0; i < state.length; i++)
          if (i == idx)
            state[i].copyWith(
              quantity: state[i].quantity + 1,
              parentNodeId: parentNodeId,
            )
          else
            state[i],
      ];
    } else {
      state = [
        ...state,
        CartItem(
          serviceId: service.id,
          serviceName: service.name,
          imageUrl: service.imageUrl,
          unitPrice: (service.basePrice ?? 0.0) + priceAdjustment,
          quantity: 1,
          minimumOrderAmount: service.minimumOrderAmount,
          parentNodeId: parentNodeId,
        ),
      ];
    }
    _save();
    unawaited(_sync.upsertItem(state.firstWhere((i) => i.serviceId == service.id)));
  }

  void removeFromCart(String serviceId) {
    state = state.where((item) => item.serviceId != serviceId).toList();
    _save();
    unawaited(_sync.deleteItem(serviceId));
  }

  void updateQuantity(String serviceId, int quantity) {
    if (quantity <= 0) {
      removeFromCart(serviceId);
      return;
    }
    state = [
      for (final item in state)
        if (item.serviceId == serviceId) item.copyWith(quantity: quantity)
        else item,
    ];
    _save();
    final updated = state.firstWhere((i) => i.serviceId == serviceId);
    unawaited(_sync.upsertItem(updated));
  }

  void clearCart() {
    state = [];
    _save();
    unawaited(_sync.clearAll());
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
