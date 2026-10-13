import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/cart_item.dart';

/// Manages carts that are not currently active — saved because the customer
/// added a service from a different root category, or because they explicitly
/// switched carts. Keyed by rootCategoryId.
///
/// Persists to SharedPreferences so saved carts survive app restarts. Remote
/// sync (Supabase cart_items) is intentionally excluded: that table represents
/// only the active cart and changing it for saved carts would require a schema
/// change. Saved carts therefore only roam within the same device.
class SavedCartsNotifier
    extends StateNotifier<Map<String, List<CartItem>>> {
  static const _storageKey = 'dodo_saved_carts_v1';

  SavedCartsNotifier() : super({}) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw == null) return;
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      state = {
        for (final entry in decoded.entries)
          entry.key: (entry.value as List<dynamic>)
              .map((e) => CartItem.fromJson(e as Map<String, dynamic>))
              .toList(),
      };
    } catch (e) {
      debugPrint('[DODO][SavedCarts] _load failed: $e');
    }
  }

  Future<void> _persist() async {
    // Capture state synchronously before any async gap.
    final snapshot = state;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _storageKey,
        jsonEncode({
          for (final entry in snapshot.entries)
            entry.key: entry.value.map((e) => e.toJson()).toList(),
        }),
      );
    } catch (e) {
      debugPrint('[DODO][SavedCarts] _persist failed: $e');
    }
  }

  /// Saves [items] as the cart for [rootCategoryId], overwriting any existing
  /// saved cart for that category. No-op when [items] is empty.
  void saveCart(String rootCategoryId, List<CartItem> items) {
    if (items.isEmpty) return;
    state = {...state, rootCategoryId: List.unmodifiable(items)};
    unawaited(_persist());
  }

  /// Removes and returns the saved cart for [rootCategoryId], or null if none.
  List<CartItem>? takeCart(String rootCategoryId) {
    final items = state[rootCategoryId];
    if (items == null) return null;
    final next = Map<String, List<CartItem>>.from(state)
      ..remove(rootCategoryId);
    state = next;
    unawaited(_persist());
    return items;
  }

  /// Removes the saved cart for [rootCategoryId] without returning it.
  void removeCart(String rootCategoryId) {
    if (!state.containsKey(rootCategoryId)) return;
    final next = Map<String, List<CartItem>>.from(state)
      ..remove(rootCategoryId);
    state = next;
    unawaited(_persist());
  }

  /// Removes the oldest saved cart when there are more than one, keeping at
  /// most one saved cart so the total (1 active + saved) never exceeds 2.
  void trimToOne() {
    if (state.length <= 1) return;
    final next = Map<String, List<CartItem>>.from(state)
      ..remove(state.keys.first);
    state = next;
    unawaited(_persist());
  }
}

final savedCartsProvider =
    StateNotifierProvider<SavedCartsNotifier, Map<String, List<CartItem>>>(
  (_) => SavedCartsNotifier(),
);
