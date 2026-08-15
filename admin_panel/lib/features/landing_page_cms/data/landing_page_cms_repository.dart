import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/models/landing_page_section.dart';

class LandingPageCmsRepository {
  static SupabaseClient get _db => Supabase.instance.client;
  static const _table = 'landing_page_sections';

  // ── Read ──────────────────────────────────────────────────────────────────

  Future<List<LandingPageSection>> fetchAll() async {
    final data = await _db
        .from(_table)
        .select()
        .order('display_order', ascending: true);
    final sections = (data as List)
        .map((e) => LandingPageSection.fromMap(e as Map<String, dynamic>))
        .toList();
    debugPrint(
      '[CMS-REPO] fetchAll: ${sections.map((s) => '${s.sectionName}:${s.displayOrder}').join(', ')}',
    );
    return sections;
  }

  // ── Create ────────────────────────────────────────────────────────────────

  Future<LandingPageSection> create({
    required String sectionType,
    required String sectionName,
    required int displayOrder,
    required Map<String, dynamic> config,
  }) async {
    final data = await _db
        .from(_table)
        .insert({
          'section_type': sectionType,
          'section_name': sectionName,
          'display_order': displayOrder,
          'is_enabled': false,
          'is_published': false,
          'config': config,
        })
        .select()
        .single();
    return LandingPageSection.fromMap(data as Map<String, dynamic>);
  }

  // ── Update ────────────────────────────────────────────────────────────────

  Future<void> updateName(String id, String name) async {
    await _db.from(_table).update({'section_name': name}).eq('id', id);
  }

  Future<void> updateEnabled(String id, {required bool isEnabled}) async {
    await _db
        .from(_table)
        .update({'is_enabled': isEnabled})
        .eq('id', id);
  }

  Future<void> updateConfig(
    String id, {
    required String sectionName,
    required Map<String, dynamic> config,
  }) async {
    await _db.from(_table).update({
      'section_name': sectionName,
      'config': config,
    }).eq('id', id);
  }

  /// Reorders sections by updating display_order on each row individually.
  /// Uses UPDATE (not upsert) so only display_order is touched — a partial
  /// upsert payload would violate NOT NULL on section_type / section_name / config.
  Future<void> reorder(List<String> orderedIds) async {
    for (int i = 0; i < orderedIds.length; i++) {
      final newOrder = (i + 1) * 10;
      try {
        final result = await _db
            .from(_table)
            .update({'display_order': newOrder})
            .eq('id', orderedIds[i])
            .select('id, display_order');
        debugPrint(
          '[CMS-REPO] UPDATE[$i] id=${orderedIds[i]} → $newOrder : ${result.length} row(s) affected, data: $result',
        );
        if (result.isEmpty) {
          throw Exception(
            'reorder UPDATE matched 0 rows for id=${orderedIds[i]} — RLS block or id not in DB',
          );
        }
      } on PostgrestException catch (e) {
        debugPrint('[CMS-REPO] reorder UPDATE[$i] FAILED — PostgrestException:');
        debugPrint('  message : ${e.message}');
        debugPrint('  code    : ${e.code}');
        debugPrint('  details : ${e.details}');
        debugPrint('  hint    : ${e.hint}');
        rethrow;
      } on Exception {
        rethrow;
      } catch (e, st) {
        debugPrint('[CMS-REPO] reorder UPDATE[$i] FAILED — unexpected: $e\n$st');
        rethrow;
      }
    }
  }

  // ── Publish ───────────────────────────────────────────────────────────────

  /// Sets is_published = true for all currently enabled sections,
  /// is_published = false for all disabled sections.
  Future<void> publishAll(List<LandingPageSection> sections) async {
    final toPublish = sections
        .where((s) => s.isEnabled)
        .map((s) => s.id)
        .toList();
    final toUnpublish = sections
        .where((s) => !s.isEnabled)
        .map((s) => s.id)
        .toList();

    if (toPublish.isNotEmpty) {
      await _db
          .from(_table)
          .update({'is_published': true})
          .inFilter('id', toPublish);
    }
    if (toUnpublish.isNotEmpty) {
      await _db
          .from(_table)
          .update({'is_published': false})
          .inFilter('id', toUnpublish);
    }
  }

  /// Unpublishes all sections (emergency take-down).
  Future<void> unpublishAll() async {
    await _db.from(_table).update({'is_published': false}).neq('id', '');
  }

  // ── Delete ────────────────────────────────────────────────────────────────

  Future<void> delete(String id) async {
    await _db.from(_table).delete().eq('id', id);
  }
}
