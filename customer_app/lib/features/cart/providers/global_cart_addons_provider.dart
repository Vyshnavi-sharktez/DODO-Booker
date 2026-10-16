import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../models/addon_model.dart';

class GlobalCartAddonsNotifier
    extends StateNotifier<Map<String, SelectedAddon>> {
  static const _activeKey = 'dodo_global_addons_v1';
  static const _savedKey = 'dodo_saved_global_addons_v1';

  // In-memory saved global addons per category (rootCategoryId → addons map).
  Map<String, Map<String, SelectedAddon>> _saved = {};

  GlobalCartAddonsNotifier() : super({}) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final activeRaw = prefs.getString(_activeKey);
    if (activeRaw != null) {
      try {
        final map = jsonDecode(activeRaw) as Map<String, dynamic>;
        state = map.map(
          (k, v) => MapEntry(
            k,
            SelectedAddon.fromJson(v as Map<String, dynamic>),
          ),
        );
      } catch (_) {}
    }
    final savedRaw = prefs.getString(_savedKey);
    if (savedRaw != null) {
      try {
        final outer = jsonDecode(savedRaw) as Map<String, dynamic>;
        _saved = outer.map(
          (catId, inner) => MapEntry(
            catId,
            (inner as Map<String, dynamic>).map(
              (k, v) => MapEntry(
                k,
                SelectedAddon.fromJson(v as Map<String, dynamic>),
              ),
            ),
          ),
        );
      } catch (_) {}
    }
  }

  Future<void> _persistActive() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _activeKey,
      jsonEncode(state.map((k, v) => MapEntry(k, v.toJson()))),
    );
  }

  Future<void> _persistSaved() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _savedKey,
      jsonEncode(
        _saved.map(
          (catId, addons) =>
              MapEntry(catId, addons.map((k, v) => MapEntry(k, v.toJson()))),
        ),
      ),
    );
  }

  void toggle(AddOnModel addon) {
    if (state.containsKey(addon.id)) {
      state = Map.from(state)..remove(addon.id);
    } else {
      state = {
        ...state,
        addon.id: SelectedAddon(
          addonId: addon.id,
          addonName: addon.name,
          addonPrice: addon.finalPrice,
          originalAddonPrice: addon.hasDiscount ? addon.price : null,
          quantity: 1,
        ),
      };
    }
    unawaited(_persistActive());
  }

  void setQuantity(String addonId, int qty) {
    if (!state.containsKey(addonId)) return;
    if (qty <= 0) {
      state = Map.from(state)..remove(addonId);
    } else {
      state = {...state, addonId: state[addonId]!.copyWith(quantity: qty)};
    }
    unawaited(_persistActive());
  }

  // Synchronously saves current active state under [fromRootId] and restores
  // [toRootId]'s previously saved state (or empty). Persists both async.
  void swapForCategory(String fromRootId, String toRootId) {
    _saved[fromRootId] = Map.from(state);
    state = Map.from(_saved[toRootId] ?? {});
    _saved.remove(toRootId);
    unawaited(_persistActive());
    unawaited(_persistSaved());
  }

  void clear() {
    state = {};
    unawaited(_persistActive());
  }
}

final globalCartAddonsProvider =
    StateNotifierProvider<GlobalCartAddonsNotifier, Map<String, SelectedAddon>>(
  (ref) => GlobalCartAddonsNotifier(),
);

final globalAddonsTotalProvider = Provider<double>((ref) {
  final addons = ref.watch(globalCartAddonsProvider);
  return addons.values.fold(0.0, (sum, a) => sum + a.addonPrice * a.quantity);
});
