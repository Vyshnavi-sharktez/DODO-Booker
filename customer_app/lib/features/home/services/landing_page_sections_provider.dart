import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/landing_page_section.dart';
import '../../../core/config/supabase_config.dart';

/// Fetches the published + enabled landing-page sections ordered by display_order.
/// Falls back to [_kDefaultSections] when Supabase is unavailable or the table
/// has not been seeded yet, so the home screen always renders correctly.
final landingPageSectionsProvider =
    FutureProvider<List<LandingPageSection>>((ref) async {
  if (SupabaseConfig.supabaseUrl.isEmpty) return _kDefaultSections;

  try {
    final data = await Supabase.instance.client
        .from('landing_page_sections')
        .select()
        .eq('is_published', true)
        .eq('is_enabled', true)
        .order('display_order', ascending: true);

    final sections = (data as List)
        .map((e) => LandingPageSection.fromMap(e as Map<String, dynamic>))
        .toList();

    return sections.isEmpty ? _kDefaultSections : sections;
  } catch (_) {
    return _kDefaultSections;
  }
});

// Mirrors the migration seed so the home screen works without Supabase.
final _kDefaultSections = const [
  LandingPageSection(
    id: 'default-hero',
    sectionType: 'hero',
    sectionName: 'Hero',
    displayOrder: 10,
    isEnabled: true,
    isPublished: true,
    config: {},
  ),
  LandingPageSection(
    id: 'default-service-grid',
    sectionType: 'service_grid',
    sectionName: 'Our Services',
    displayOrder: 20,
    isEnabled: true,
    isPublished: true,
    config: {'title': 'Our Services', 'show_see_all': true},
  ),
  LandingPageSection(
    id: 'default-sub-services',
    sectionType: 'sub_services',
    sectionName: 'Sub Services',
    displayOrder: 30,
    isEnabled: true,
    isPublished: true,
    config: {'title': 'Sub Services'},
  ),
  LandingPageSection(
    id: 'default-why-dodo',
    sectionType: 'why_dodo',
    sectionName: 'Why Choose DODO',
    displayOrder: 40,
    isEnabled: true,
    isPublished: true,
    config: {},
  ),
  LandingPageSection(
    id: 'default-how-it-works',
    sectionType: 'how_it_works',
    sectionName: 'How DODO Booker Works',
    displayOrder: 50,
    isEnabled: true,
    isPublished: true,
    config: {},
  ),
  LandingPageSection(
    id: 'default-special-offers',
    sectionType: 'special_offers',
    sectionName: 'Special Offers',
    displayOrder: 60,
    isEnabled: true,
    isPublished: true,
    config: {},
  ),
  LandingPageSection(
    id: 'default-popular',
    sectionType: 'popular_near_you',
    sectionName: 'Popular Near You',
    displayOrder: 70,
    isEnabled: true,
    isPublished: true,
    config: {'title': 'Popular Near You', 'show_see_all': true},
  ),
  LandingPageSection(
    id: 'default-testimonials',
    sectionType: 'testimonials',
    sectionName: 'Customer Reviews',
    displayOrder: 80,
    isEnabled: true,
    isPublished: true,
    config: {},
  ),
  LandingPageSection(
    id: 'default-footer',
    sectionType: 'footer',
    sectionName: 'Footer',
    displayOrder: 90,
    isEnabled: true,
    isPublished: true,
    config: {},
  ),
];
