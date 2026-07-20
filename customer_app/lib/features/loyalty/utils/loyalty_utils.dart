import '../models/loyalty_settings_model.dart';

/// Mirrors the backend `award_loyalty_points` trigger logic.
/// Used by the checkout screen and loyalty earn badges to compute points consistently.
int computeLoyaltyPoints(
  Map<String, dynamic>? cfg,
  LoyaltySettingsModel global,
  double price,
) {
  if (cfg == null) {
    return (price / 100).floor() * global.earnPer100;
  }
  if (cfg['earn_enabled'] == false) return 0;
  final rule = cfg['earn_rule'] as String?;
  if (rule == 'fixed') {
    return (cfg['fixed_points'] as num?)?.toInt() ?? 0;
  }
  if (rule == 'percentage') {
    final per = (cfg['earn_per_100'] as num?)?.toInt();
    if (per != null) return (price / 100).floor() * per;
  }
  return (price / 100).floor() * global.earnPer100;
}
