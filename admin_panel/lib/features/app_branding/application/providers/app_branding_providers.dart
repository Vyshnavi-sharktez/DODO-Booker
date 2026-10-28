import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/application/providers/auth_provider.dart';
import '../../data/app_branding_repository.dart';
import '../../domain/models/app_branding_model.dart';

// ── Repository provider ───────────────────────────────────────────────────────

final appBrandingRepositoryProvider = Provider<AppBrandingRepository>((ref) {
  return AppBrandingRepository(ref.watch(supabaseClientProvider));
});

// ── Notifier ──────────────────────────────────────────────────────────────────

class AppBrandingNotifier
    extends StateNotifier<AsyncValue<List<AppBrandingModel>>> {
  AppBrandingNotifier(this._repo) : super(const AsyncValue.loading()) {
    _load();
  }

  final AppBrandingRepository _repo;

  Future<void> _load() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_repo.loadAll);
  }

  Future<void> refresh() => _load();

  /// Uploads a new icon and persists the URL. Updates optimistic local state.
  Future<void> uploadAndSave({
    required String appId,
    required Uint8List bytes,
    required String extension,
  }) async {
    final url = await _repo.uploadIcon(
      appId: appId,
      bytes: bytes,
      extension: extension,
    );
    await _repo.saveIconUrl(appId, url);
    _updateLocal(appId, url);
  }

  /// Clears the icon URL for [appId] (does not delete the storage object).
  Future<void> removeIcon(String appId) async {
    await _repo.saveIconUrl(appId, null);
    _updateLocal(appId, null);
  }

  void _updateLocal(String appId, String? iconUrl) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncValue.data(
      current.map((e) {
        if (e.appId != appId) return e;
        return iconUrl != null
            ? e.copyWith(iconUrl: iconUrl)
            : e.copyWith(clearIcon: true);
      }).toList(),
    );
  }
}

final appBrandingNotifierProvider = StateNotifierProvider<AppBrandingNotifier,
    AsyncValue<List<AppBrandingModel>>>(
  (ref) => AppBrandingNotifier(ref.watch(appBrandingRepositoryProvider)),
);

// ── Lightweight sidebar provider ──────────────────────────────────────────────
// Loads only the admin_panel icon URL — used by the sidebar brand widget on
// every page.  Separate from the full notifier to avoid loading all three rows
// just to render the sidebar.

final adminPanelBrandingIconProvider = FutureProvider<String?>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final data = await client
      .from('app_branding')
      .select('icon_url')
      .eq('app_id', 'admin_panel')
      .maybeSingle();
  return data?['icon_url'] as String?;
});
