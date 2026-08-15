import 'package:flutter/material.dart';

/// All section types supported by the Landing Page CMS.
///
/// Canonical types (approved landing-page structure) come first.
/// Generic/reusable types follow.
enum SectionType {
  // ── Canonical approved sections ──────────────────────────────────────────
  hero,
  serviceGrid,
  subServices,
  whyDodo,
  howItWorks,
  specialOffers,
  popularNearYou,
  testimonials,
  footer,
  // ── Generic reusable section types ───────────────────────────────────────
  contentGrid,
  promoBanner,
  faq,
  cta;

  String get dbKey => switch (this) {
        SectionType.hero           => 'hero',
        SectionType.serviceGrid    => 'service_grid',
        SectionType.subServices    => 'sub_services',
        SectionType.whyDodo        => 'why_dodo',
        SectionType.howItWorks     => 'how_it_works',
        SectionType.specialOffers  => 'special_offers',
        SectionType.popularNearYou => 'popular_near_you',
        SectionType.testimonials   => 'testimonials',
        SectionType.footer         => 'footer',
        SectionType.contentGrid    => 'content_grid',
        SectionType.promoBanner    => 'promo_banner',
        SectionType.faq            => 'faq',
        SectionType.cta            => 'cta',
      };

  String get displayName => switch (this) {
        SectionType.hero           => 'Hero',
        SectionType.serviceGrid    => 'Service / Category Grid',
        SectionType.subServices    => 'Sub Services',
        SectionType.whyDodo        => 'Why Choose DODO',
        SectionType.howItWorks     => 'How It Works',
        SectionType.specialOffers  => 'Special Offers',
        SectionType.popularNearYou => 'Popular Near You',
        SectionType.testimonials   => 'Testimonials',
        SectionType.footer         => 'Footer',
        SectionType.contentGrid    => 'Content Grid',
        SectionType.promoBanner    => 'Promotional Banner',
        SectionType.faq            => 'FAQ',
        SectionType.cta            => 'Call to Action',
      };

  IconData get icon => switch (this) {
        SectionType.hero           => Icons.view_carousel_rounded,
        SectionType.serviceGrid    => Icons.grid_view_rounded,
        SectionType.subServices    => Icons.home_repair_service_rounded,
        SectionType.whyDodo        => Icons.verified_rounded,
        SectionType.howItWorks     => Icons.linear_scale_rounded,
        SectionType.specialOffers  => Icons.local_offer_rounded,
        SectionType.popularNearYou => Icons.trending_up_rounded,
        SectionType.testimonials   => Icons.rate_review_rounded,
        SectionType.footer         => Icons.web_asset_rounded,
        SectionType.contentGrid    => Icons.dashboard_rounded,
        SectionType.promoBanner    => Icons.campaign_rounded,
        SectionType.faq            => Icons.help_outline_rounded,
        SectionType.cta            => Icons.ads_click_rounded,
      };

  String get description => switch (this) {
        SectionType.hero           => 'Main hero banner with headline and CTAs',
        SectionType.serviceGrid    => 'Root service categories carousel',
        SectionType.subServices    => 'Bookable sub-services grid',
        SectionType.whyDodo        => 'Trust items — verified, transparent, secure',
        SectionType.howItWorks     => 'Step-by-step booking process',
        SectionType.specialOffers  => 'Active coupon/offer cards (data-driven)',
        SectionType.popularNearYou => 'Services popular in the last 90 days',
        SectionType.testimonials   => 'Customer review cards (data-driven)',
        SectionType.footer         => 'Site-wide footer (always full-width)',
        SectionType.contentGrid    => 'Custom image + text item grid',
        SectionType.promoBanner    => 'Promotional banner with optional image',
        SectionType.faq            => 'Expandable FAQ list',
        SectionType.cta            => 'Single call-to-action panel',
      };

  bool get isCanonical => index < SectionType.contentGrid.index;

  /// Default config when creating a new section of this type.
  Map<String, dynamic> get defaultConfig => switch (this) {
        SectionType.hero => {
            'headline': 'Expert Home Services, On Demand',
            'subheadline': 'Trusted professionals for all your home needs — booked in minutes.',
            'cta_primary_text': 'Book Now',
            'cta_secondary_text': 'Explore Services',
          },
        SectionType.serviceGrid => {
            'title': 'Our Services',
            'show_see_all': true,
          },
        SectionType.subServices => {'title': 'Sub Services'},
        SectionType.whyDodo => {
            'title': 'Why Choose DODO Booker?',
            'subtitle': 'Everything you need for a seamless home services experience.',
            'items': [
              {'icon': 'verified_user_rounded', 'title': 'Verified Professionals', 'description': 'Every service provider is background-checked and certified before joining our platform.'},
              {'icon': 'receipt_long_rounded',  'title': 'Transparent Pricing',    'description': 'No hidden charges — what you see is what you pay. Get instant quotes upfront.'},
              {'icon': 'lock_rounded',           'title': 'Secure Booking',         'description': 'Your payments and personal data are protected with bank-grade encryption.'},
            ],
          },
        SectionType.howItWorks => {
            'title': 'How DODO Booker Works',
            'steps': [
              {'icon': 'search_rounded',        'title': 'Choose a Service',    'description': 'Browse our wide range of professional home services and find exactly what you need.'},
              {'icon': 'access_time_rounded',   'title': 'Pick a Time',         'description': 'Select a date and time slot that works best for your schedule.'},
              {'icon': 'verified_user_rounded', 'title': 'Book a Professional', 'description': 'Get matched with a verified, background-checked professional near you.'},
              {'icon': 'check_circle_rounded',  'title': 'Get It Done',         'description': 'Relax while our expert handles the job to your complete satisfaction.'},
            ],
          },
        SectionType.specialOffers  => {},
        SectionType.popularNearYou => {'title': 'Popular Near You', 'show_see_all': true},
        SectionType.testimonials   => {'title': 'What Our Customers Say'},
        SectionType.footer         => {},
        SectionType.contentGrid    => {
            'title': 'Featured Content',
            'subtitle': '',
            'items': [],
          },
        SectionType.promoBanner => {
            'title': 'Special Promotion',
            'subtitle': 'Limited time offer — book now and save.',
            'cta_text': 'Learn More',
            'cta_url': '/',
          },
        SectionType.faq => {
            'title': 'Frequently Asked Questions',
            'items': [],
          },
        SectionType.cta => {
            'title': 'Ready to Get Started?',
            'subtitle': 'Book your first professional home service today.',
            'button_text': 'Book Now',
            'button_url': '/',
          },
      };

  static SectionType? fromDbKey(String key) {
    for (final type in values) {
      if (type.dbKey == key) return type;
    }
    return null;
  }
}
