import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/landing_page_cms_repository.dart';
import '../../domain/models/landing_page_section.dart';

final landingPageCmsRepositoryProvider =
    Provider<LandingPageCmsRepository>((ref) => LandingPageCmsRepository());

/// All sections, ordered by display_order. Admin sees draft + published alike.
final landingPageSectionsProvider =
    FutureProvider<List<LandingPageSection>>((ref) async {
  return ref.read(landingPageCmsRepositoryProvider).fetchAll();
});

/// Notifier that manages the mutable in-memory section list for the CMS page.
/// Editing operations update state optimistically and persist to Supabase.
class LandingPageCmsNotifier
    extends AutoDisposeAsyncNotifier<List<LandingPageSection>> {
  LandingPageCmsRepository get _repo =>
      ref.read(landingPageCmsRepositoryProvider);

  /// Tracks the in-flight Supabase display_order persist from the last drag.
  /// publishAll() awaits this so it never reads stale order from the DB.
  Future<void>? _pendingReorder;

  @override
  Future<List<LandingPageSection>> build() async {
    return _repo.fetchAll();
  }

  // ── Enable / disable ───────────────────────────────────────────────────────

  Future<void> setEnabled(String id, {required bool enabled}) async {
    state = state.whenData((list) => [
          for (final s in list)
            if (s.id == id) s.copyWith(isEnabled: enabled) else s,
        ]);
    await _repo.updateEnabled(id, isEnabled: enabled);
  }

  // ── Reorder ────────────────────────────────────────────────────────────────

  Future<void> reorder(int oldIndex, int newIndex) async {
    final current = state.valueOrNull;
    if (current == null) return;

    final list = List<LandingPageSection>.from(current);
    final item = list.removeAt(oldIndex);
    final insertAt = newIndex > oldIndex ? newIndex - 1 : newIndex;
    list.insert(insertAt, item);

    final reordered = [
      for (int i = 0; i < list.length; i++)
        list[i].copyWith(displayOrder: (i + 1) * 10),
    ];

    // Optimistic local update — Admin CMS reflects new order immediately.
    state = AsyncData(reordered);

    // Persist to Supabase. Track the future so publishAll() can await it.
    _pendingReorder = _repo.reorder(reordered.map((s) => s.id).toList());
    try {
      await _pendingReorder!;
    } catch (e, st) {
      // Revert local state so Admin CMS shows the true Supabase order,
      // then rethrow so the page can surface a SnackBar to the admin.
      debugPrint('[CMS] reorder persist failed — reverting: $e\n$st');
      state = AsyncData(current);
      rethrow;
    } finally {
      _pendingReorder = null;
    }
  }

  // ── Save config / name ─────────────────────────────────────────────────────

  Future<void> saveSection(
    String id, {
    required String sectionName,
    required Map<String, dynamic> config,
  }) async {
    state = state.whenData((list) => [
          for (final s in list)
            if (s.id == id) s.copyWith(sectionName: sectionName, config: config) else s,
        ]);
    await _repo.updateConfig(id, sectionName: sectionName, config: config);
  }

  // ── Create ─────────────────────────────────────────────────────────────────

  Future<void> createSection({
    required String sectionType,
    required String sectionName,
    required Map<String, dynamic> config,
  }) async {
    final current = state.valueOrNull ?? [];
    final nextOrder = (current.isEmpty ? 0 : current.last.displayOrder) + 10;

    final created = await _repo.create(
      sectionType: sectionType,
      sectionName: sectionName,
      displayOrder: nextOrder,
      config: config,
    );
    state = AsyncData([...current, created]);
  }

  // ── Delete ─────────────────────────────────────────────────────────────────

  Future<void> deleteSection(String id) async {
    state = state.whenData(
        (list) => list.where((s) => s.id != id).toList());
    await _repo.delete(id);
  }

  // ── Publish ────────────────────────────────────────────────────────────────

  Future<void> publishAll() async {
    // Fix 1: wait for any in-flight reorder persist. If the user taps
    // Publish All immediately after dragging, the display_order upsert may
    // still be in flight — we must not overwrite local state before it lands.
    await _pendingReorder?.catchError((_) {});

    final current = state.valueOrNull;
    if (current == null) return;
    await _repo.publishAll(current);

    // Fix 2: update is_published optimistically from current local state.
    // A full fetchAll() would overwrite display_order with whatever Supabase
    // returns at that instant, discarding the reordered local list.
    // publishAll() semantics: is_published = is_enabled for every section.
    state = AsyncData(
      current.map((s) => s.copyWith(isPublished: s.isEnabled)).toList(),
    );
  }
}

final landingPageCmsNotifierProvider = AsyncNotifierProvider.autoDispose<
    LandingPageCmsNotifier, List<LandingPageSection>>(
  LandingPageCmsNotifier.new,
);
