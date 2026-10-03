import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/models/landing_page_section.dart';

// Mirrors supabase/migrations/20260815000001_create_landing_page_sections.sql
// Used to bootstrap the table when it exists but has no rows.
const _kSeedRows = [
  // ── 9 enabled + published ────────────────────────────────────────────────
  _Seed('hero', 'Hero', 10, true, true, {
    'headline': 'Expert Home Services, On Demand',
    'subheadline':
        'Trusted professionals for all your home needs — booked in minutes.',
    'cta_primary_text': 'Book Now',
    'cta_secondary_text': 'Explore Services',
  }),
  _Seed('service_grid', 'Our Services', 20, true, true,
      {'title': 'Our Services', 'show_see_all': true}),
  _Seed('sub_services', 'Sub Services', 30, true, true,
      {'title': 'Sub Services'}),
  _Seed('why_dodo', 'Why Choose DODO', 40, true, true, {
    'title': 'Why Choose DODO Booker?',
    'subtitle': 'Everything you need for a seamless home services experience.',
    'items': [
      {
        'icon': 'verified_user_rounded',
        'title': 'Verified Professionals',
        'description':
            'Every service provider is background-checked and certified before joining our platform.',
      },
      {
        'icon': 'receipt_long_rounded',
        'title': 'Transparent Pricing',
        'description':
            'No hidden charges — what you see is what you pay. Get instant quotes upfront.',
      },
      {
        'icon': 'lock_rounded',
        'title': 'Secure Booking',
        'description':
            'Your payments and personal data are protected with bank-grade encryption.',
      },
    ],
  }),
  _Seed('how_it_works', 'How DODO Booker Works', 50, true, true, {
    'title': 'How DODO Booker Works',
    'steps': [
      {
        'icon': 'search_rounded',
        'title': 'Choose a Service',
        'description':
            'Browse our wide range of professional home services and find exactly what you need.',
      },
      {
        'icon': 'access_time_rounded',
        'title': 'Pick a Time',
        'description':
            'Select a date and time slot that works best for your schedule.',
      },
      {
        'icon': 'verified_user_rounded',
        'title': 'Book a Professional',
        'description':
            'Get matched with a verified, background-checked professional near you.',
      },
      {
        'icon': 'check_circle_rounded',
        'title': 'Get It Done',
        'description':
            'Relax while our expert handles the job to your complete satisfaction.',
      },
    ],
  }),
  _Seed('special_offers', 'Special Offers', 60, true, true, {}),
  _Seed('popular_near_you', 'Popular Near You', 70, true, true,
      {'title': 'Popular Near You', 'show_see_all': true}),
  _Seed('testimonials', 'Customer Reviews', 80, true, true,
      {'title': 'What Our Customers Say'}),
  _Seed('footer', 'Footer', 90, true, true, {}),
  // ── 4 disabled + unpublished ─────────────────────────────────────────────
  _Seed('content_grid', 'Thoughtful Creations', 100, false, false, {
    'title': 'Thoughtful Creations',
    'subtitle': 'Carefully curated services for your home.',
    'items': [],
  }),
  _Seed('promo_banner', 'Promotional Banner', 110, false, false, {
    'title': 'Special Promotion',
    'subtitle': 'Limited time offer — book now and save.',
    'cta_text': 'Learn More',
    'cta_url': '/',
  }),
  _Seed('faq', 'FAQ', 120, false, false, {
    'title': 'Frequently Asked Questions',
    'items': [],
  }),
  _Seed('cta', 'Get Started', 130, false, false, {
    'title': 'Ready to Get Started?',
    'subtitle': 'Book your first professional home service today.',
    'button_text': 'Book Now',
    'button_url': '/',
  }),
];

class _Seed {
  final String type, name;
  final int order;
  final bool enabled, published;
  final Map<String, dynamic> config;
  const _Seed(
      this.type, this.name, this.order, this.enabled, this.published, this.config);
  Map<String, dynamic> toRow() => {
        'section_type': type,
        'section_name': name,
        'display_order': order,
        'is_enabled': enabled,
        'is_published': published,
        'config': config,
      };
}

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

  // ── Seed ──────────────────────────────────────────────────────────────────

  /// Inserts the canonical 13-section seed when the table is empty.
  /// Safe to call multiple times only when the table is genuinely empty —
  /// the notifier checks before calling.
  Future<void> seedDefaults() async {
    await _db.from(_table).insert(_kSeedRows.map((s) => s.toRow()).toList());
    debugPrint('[CMS-REPO] seedDefaults: inserted ${_kSeedRows.length} rows');
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
