import 'package:flutter/material.dart';

/// Maps icon_key strings (stored in `categories.icon_key`) to Flutter IconData.
/// When no key is stored, falls back to name-based substring matching so that
/// the app continues to work before the migration is applied.
///
/// To support a new icon: add an entry here and set icon_key in the DB row.
class IconRegistry {
  const IconRegistry._();

  static const _map = <String, IconData>{
    'cleaning_services':         Icons.cleaning_services,
    'cleaning_services_rounded': Icons.cleaning_services_rounded,
    'plumbing':                  Icons.plumbing,
    'plumbing_rounded':          Icons.plumbing_rounded,
    'electrical_services':       Icons.electrical_services,
    'electrical_services_rounded': Icons.electrical_services_rounded,
    'format_paint':              Icons.format_paint,
    'format_paint_rounded':      Icons.format_paint_rounded,
    'build':                     Icons.build,
    'bug_report':                Icons.bug_report,
    'bug_report_rounded':        Icons.bug_report_rounded,
    'kitchen':                   Icons.kitchen,
    'ac_unit_rounded':           Icons.ac_unit_rounded,
    'local_shipping':            Icons.local_shipping,
    'local_shipping_rounded':    Icons.local_shipping_rounded,
    'content_cut':               Icons.content_cut,
    'yard':                      Icons.yard,
    'local_laundry_service':     Icons.local_laundry_service,
    'chair_rounded':             Icons.chair_rounded,
    'home_repair_service':       Icons.home_repair_service,
    'home_repair_service_rounded': Icons.home_repair_service_rounded,
  };

  /// Returns the IconData for [iconKey] if registered, otherwise falls back to
  /// substring-matching on [fallbackName].
  static IconData resolve(String? iconKey, String? fallbackName) {
    if (iconKey != null && iconKey.isNotEmpty) {
      final icon = _map[iconKey];
      if (icon != null) return icon;
    }
    return _byName(fallbackName ?? '');
  }

  static IconData _byName(String name) {
    final n = name.toLowerCase();
    if (n.contains('clean'))                           return Icons.cleaning_services;
    if (n.contains('plumb'))                           return Icons.plumbing;
    if (n.contains('electr'))                          return Icons.electrical_services;
    if (n.contains('paint'))                           return Icons.format_paint;
    if (n.contains('carpen'))                          return Icons.build;
    if (n.contains('pest'))                            return Icons.bug_report;
    if (n.contains('appli'))                           return Icons.kitchen;
    if (n.contains('shift') || n.contains('moving'))   return Icons.local_shipping;
    if (n.contains('salon') || n.contains('beauty'))   return Icons.content_cut;
    if (n.contains('garden'))                          return Icons.yard;
    if (n.contains('laundry'))                         return Icons.local_laundry_service;
    return Icons.home_repair_service;
  }
}
