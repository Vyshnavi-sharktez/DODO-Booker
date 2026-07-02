import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/cart_item.dart';
import '../../../models/service_model.dart';
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
  /// remote wins for items in both; local-only items are upserted to remote.
  Future<void> loadFromRemote() async {
    final remoteItems = await _sync.fetchAll();
    if (remoteItems.isEmpty && state.isEmpty) return;

    final merged = <String, CartItem>{
      for (final item in state) item.serviceId: item,
    };

    // Remote wins for items in both; remote-only items get added
    for (final remote in remoteItems) {
      merged[remote.serviceId] = remote;
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

  void addToCart(ServiceModel service, {double priceAdjustment = 0.0}) {
    debugPrint('[DODO][CartSync][1] addToCart() entered — serviceId=${service.id} name=${service.name}');
    final idx = state.indexWhere((item) => item.serviceId == service.id);
    if (idx >= 0) {
      state = [
        for (int i = 0; i < state.length; i++)
          if (i == idx) state[i].copyWith(quantity: state[i].quantity + 1)
          else state[i],
      ];
    } else {
      state = [
        ...state,
        CartItem(
          serviceId: service.id,
          serviceName: service.name,
          imageUrl: service.imageUrl,
          unitPrice: service.startingPrice + priceAdjustment,
          quantity: 1,
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
