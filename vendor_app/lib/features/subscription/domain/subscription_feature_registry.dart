/// Central registry of all vendor subscription permission features.
///
/// ADD A NEW FEATURE: append one [SubscriptionFeature] entry to
/// [kSubscriptionFeatures].  The key and defaultValue must match exactly what
/// is stored in `subscription_plans.permissions` (global plans) and
/// `vendor_subscriptions.subscription_permissions` (catalog subscription
/// snapshot).
///
/// ENFORCEMENT stays in code: add the Dart/SQL enforcement logic separately in
/// the relevant code path (e.g. a booking guard, a SQL trigger).  Only the
/// feature metadata — key, label, description, type, default — lives here.
///
/// KEEP IN SYNC: admin_panel contains an identical copy of this file at
/// admin_panel/lib/features/vendor_subscriptions/domain/subscription_feature_registry.dart
/// Update both files together whenever this list changes.

// No Flutter or external imports — pure Dart so this file can be used anywhere.

/// Whether a subscription feature is a boolean on/off toggle, a numeric
/// percentage value (0–100), or a non-negative integer count limit.
enum SubscriptionFeatureType {
  /// A boolean capability — either granted or not.
  toggle,

  /// A numeric percentage, e.g. commission reduction (0–100).
  percent,

  /// A non-negative integer cap, e.g. maximum number of custom services.
  /// Absent from permissions = no limit.
  quantity,
}

/// Metadata for a single subscription permission feature.
class SubscriptionFeature {
  const SubscriptionFeature({
    required this.key,
    required this.label,
    required this.description,
    required this.type,
    required this.defaultValue,
    this.limitKey,
  });

  /// The exact string key stored in the permissions JSONB and referenced by
  /// SQL enforcement functions.  Never change an existing key — it would
  /// silently break all stored plans and live subscriptions.
  final String key;

  /// Short human-readable name shown in admin plan forms and vendor plan cards.
  final String label;

  /// One-sentence explanation of what this feature grants the vendor.
  final String description;

  /// Controls which input widget is rendered in admin forms.
  final SubscriptionFeatureType type;

  /// Fallback value used when the feature is absent from a plan's permissions
  /// map.  Must be [bool] for [SubscriptionFeatureType.toggle], [double] for
  /// [SubscriptionFeatureType.percent], and [null] for
  /// [SubscriptionFeatureType.quantity] (null = unlimited).
  final dynamic defaultValue;

  /// Optional permissions JSONB key for a per-feature integer count limit.
  /// Only valid on [SubscriptionFeatureType.toggle] features.
  /// [null] means this feature has no configurable quantity limit.
  /// When present and absent from a plan's permissions map, the limit is
  /// treated as unlimited (no cap).
  final String? limitKey;
}

/// The canonical ordered list of subscription features.
///
/// Display order in admin forms and vendor plan cards follows this list.
/// All five entries mirror the keys currently stored in the database and
/// referenced by existing SQL functions and Dart model getters.
const List<SubscriptionFeature> kSubscriptionFeatures = [
  SubscriptionFeature(
    key: SubscriptionFeatureKeys.allowCod,
    label: 'Allow COD Payments',
    description: 'Vendor can receive cash-on-delivery bookings.',
    type: SubscriptionFeatureType.toggle,
    defaultValue: false,
    limitKey: SubscriptionFeatureKeys.allowCodLimit,
    // Enforced by: check_vendor_cod_eligibility() SQL function (migrations
    // 20260727000001, 20260728000001) and booking_assignment_dialog.dart.
  ),
  SubscriptionFeature(
    key: SubscriptionFeatureKeys.allowBookingAssignment,
    label: 'Booking Assignment',
    description: 'Admin can manually assign bookings to this vendor.',
    type: SubscriptionFeatureType.toggle,
    defaultValue: false,
    limitKey: SubscriptionFeatureKeys.allowBookingAssignmentLimit,
    // Enforcement: not yet wired up — stored and displayed only.
  ),
  SubscriptionFeature(
    key: SubscriptionFeatureKeys.maxCustomServices,
    label: 'Max Custom Services',
    description: 'Maximum number of active custom services the vendor can have. Leave empty for no limit.',
    type: SubscriptionFeatureType.quantity,
    defaultValue: null,
    // Enforced by: _CreateServiceDialogState._submit() in services_page.dart.
  ),
  SubscriptionFeature(
    key: SubscriptionFeatureKeys.priorityListing,
    label: 'Priority Listing',
    description: 'Vendor appears higher in customer search results.',
    type: SubscriptionFeatureType.toggle,
    defaultValue: false,
    // Enforcement: not yet wired up — stored and displayed only.
  ),
  SubscriptionFeature(
    key: SubscriptionFeatureKeys.allowCustomPrice,
    label: 'Custom Service Pricing',
    description: 'Vendor can set custom prices on their own services.',
    type: SubscriptionFeatureType.toggle,
    defaultValue: false,
    // Enforced by: update_vendor_service_custom_price() SQL function
    // (migration 20260903000001).
  ),
  SubscriptionFeature(
    key: SubscriptionFeatureKeys.reducedCommissionPct,
    label: 'Reduced Commission',
    description:
        'Platform commission reduction applied at settlement (0–100 %).',
    type: SubscriptionFeatureType.percent,
    defaultValue: 0.0,
    // Enforcement: not yet wired up — stored and displayed only.
  ),
];

/// Typed constants for every feature key.
///
/// Use these instead of bare string literals in Dart enforcement code so that
/// a key rename surfaces as a compile error rather than a silent bug.
/// SQL functions must still use the matching string directly — keep them in
/// sync with any rename here.
abstract final class SubscriptionFeatureKeys {
  static const String allowCod = 'allow_cod';
  static const String allowCodLimit = 'allow_cod_limit';
  static const String allowBookingAssignment = 'allow_booking_assignment';
  static const String allowBookingAssignmentLimit = 'allow_booking_assignment_limit';
  static const String priorityListing = 'priority_listing';
  static const String reducedCommissionPct = 'reduced_commission_pct';
  static const String allowCustomPrice = 'allow_custom_price';
  static const String maxCustomServices = 'max_custom_services';
}
