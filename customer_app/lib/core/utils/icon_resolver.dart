import 'package:flutter/material.dart';

/// Resolves a Material icon name string (as stored in CMS config JSONB)
/// to an [IconData]. Returns [fallback] for unrecognised names.
IconData resolveIconData(String? name, [IconData fallback = Icons.circle_outlined]) {
  if (name == null) return fallback;
  return _kIconMap[name] ?? fallback;
}

const _kIconMap = <String, IconData>{
  'verified_user_rounded': Icons.verified_user_rounded,
  'receipt_long_rounded': Icons.receipt_long_rounded,
  'lock_rounded': Icons.lock_rounded,
  'search_rounded': Icons.search_rounded,
  'access_time_rounded': Icons.access_time_rounded,
  'check_circle_rounded': Icons.check_circle_rounded,
  'star_rounded': Icons.star_rounded,
  'home_rounded': Icons.home_rounded,
  'build_rounded': Icons.build_rounded,
  'handyman_rounded': Icons.handyman_rounded,
  'cleaning_services_rounded': Icons.cleaning_services_rounded,
  'electrical_services_rounded': Icons.electrical_services_rounded,
  'plumbing_rounded': Icons.plumbing_rounded,
  'air_rounded': Icons.air_rounded,
  'carpenter_rounded': Icons.carpenter_rounded,
  'support_agent_rounded': Icons.support_agent_rounded,
  'thumb_up_rounded': Icons.thumb_up_rounded,
  'shield_rounded': Icons.shield_rounded,
  'local_offer_rounded': Icons.local_offer_rounded,
  'payment_rounded': Icons.payment_rounded,
  'calendar_today_rounded': Icons.calendar_today_rounded,
  'bolt_rounded': Icons.bolt_rounded,
  'eco_rounded': Icons.eco_rounded,
  'water_drop_rounded': Icons.water_drop_rounded,
  'lightbulb_rounded': Icons.lightbulb_rounded,
  'person_search_rounded': Icons.person_search_rounded,
  'groups_rounded': Icons.groups_rounded,
  'rocket_launch_rounded': Icons.rocket_launch_rounded,
  'timer_rounded': Icons.timer_rounded,
  'workspace_premium_rounded': Icons.workspace_premium_rounded,
};

/// All supported icon name/label pairs — used in admin dropdowns.
const kSupportedIcons = <({String name, String label})>[
  (name: 'verified_user_rounded',      label: 'Verified User'),
  (name: 'receipt_long_rounded',       label: 'Receipt / Pricing'),
  (name: 'lock_rounded',               label: 'Lock / Security'),
  (name: 'search_rounded',             label: 'Search'),
  (name: 'access_time_rounded',        label: 'Clock / Time'),
  (name: 'check_circle_rounded',       label: 'Check Circle / Done'),
  (name: 'star_rounded',               label: 'Star'),
  (name: 'home_rounded',               label: 'Home'),
  (name: 'build_rounded',              label: 'Build / Tool'),
  (name: 'handyman_rounded',           label: 'Handyman'),
  (name: 'cleaning_services_rounded',  label: 'Cleaning'),
  (name: 'electrical_services_rounded',label: 'Electrical'),
  (name: 'plumbing_rounded',           label: 'Plumbing'),
  (name: 'air_rounded',                label: 'AC / Air'),
  (name: 'carpenter_rounded',          label: 'Carpenter'),
  (name: 'support_agent_rounded',      label: 'Support'),
  (name: 'thumb_up_rounded',           label: 'Thumb Up'),
  (name: 'shield_rounded',             label: 'Shield'),
  (name: 'local_offer_rounded',        label: 'Offer / Tag'),
  (name: 'payment_rounded',            label: 'Payment'),
  (name: 'calendar_today_rounded',     label: 'Calendar'),
  (name: 'bolt_rounded',               label: 'Bolt / Speed'),
  (name: 'eco_rounded',                label: 'Eco'),
  (name: 'water_drop_rounded',         label: 'Water'),
  (name: 'lightbulb_rounded',          label: 'Idea / Tip'),
  (name: 'person_search_rounded',      label: 'Person Search'),
  (name: 'groups_rounded',             label: 'Team / Group'),
  (name: 'rocket_launch_rounded',      label: 'Launch / Fast'),
  (name: 'timer_rounded',              label: 'Timer'),
  (name: 'workspace_premium_rounded',  label: 'Premium'),
];
