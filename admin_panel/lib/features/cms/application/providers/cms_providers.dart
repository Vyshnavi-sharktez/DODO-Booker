import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../auth/application/providers/auth_provider.dart';
import '../../data/cms_repository.dart';
import '../../domain/models/cms_page.dart';

final cmsRepositoryProvider = Provider<CmsRepository>((ref) {
  return CmsRepository(ref.watch(supabaseClientProvider));
});

class CmsPagesNotifier extends StateNotifier<AsyncValue<List<CmsPage>>> {
  final CmsRepository _repo;

  CmsPagesNotifier(this._repo) : super(const AsyncValue.loading()) {
    _load();
  }

  Future<void> _load() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_repo.fetchPages);
  }

  Future<void> refresh() => _load();

  Future<void> createPage({
    required String pageSlug,
    required String pageTitle,
    String? pageContent,
    required bool isPublished,
  }) async {
    final page = await _repo.createPage(
      pageSlug: pageSlug,
      pageTitle: pageTitle,
      pageContent: pageContent,
      isPublished: isPublished,
    );
    state = AsyncValue.data([page, ...(state.valueOrNull ?? [])]);
  }

  Future<void> updatePage(
    String id, {
    required String pageSlug,
    required String pageTitle,
    String? pageContent,
    required bool isPublished,
  }) async {
    final updated = await _repo.updatePage(
      id,
      pageSlug: pageSlug,
      pageTitle: pageTitle,
      pageContent: pageContent,
      isPublished: isPublished,
    );
    final current = state.valueOrNull ?? [];
    state = AsyncValue.data(
      current.map((p) => p.id == id ? updated : p).toList(),
    );
  }

  Future<void> deletePage(String id) async {
    await _repo.deletePage(id);
    final current = state.valueOrNull ?? [];
    state = AsyncValue.data(current.where((p) => p.id != id).toList());
  }

  Future<void> togglePublished(
    String id, {
    required bool currentIsPublished,
  }) async {
    final newVal = !currentIsPublished;
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncValue.data(
        current
            .map((p) => p.id == id ? p.copyWith(isPublished: newVal) : p)
            .toList(),
      );
    }
    try {
      await _repo.updatePublished(id, isPublished: newVal);
    } catch (e) {
      await _load();
      rethrow;
    }
  }
}

final cmsPagesNotifierProvider =
    StateNotifierProvider<CmsPagesNotifier, AsyncValue<List<CmsPage>>>(
  (ref) => CmsPagesNotifier(ref.watch(cmsRepositoryProvider)),
);
