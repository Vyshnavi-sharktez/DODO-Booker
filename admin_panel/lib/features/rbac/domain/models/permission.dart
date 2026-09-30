class Permission {
  final String id;
  final String name;
  final String? description;
  final String module;

  const Permission({
    required this.id,
    required this.name,
    this.description,
    required this.module,
  });

  static const Map<String, String> _defaultDescriptions = {
    'booking.view': 'View and manage bookings, scheduling requests, and dispatch analytics.',
    'category.view': 'View and manage service categories, catalog nodes, and AMC plans.',
    'coupon.view': 'View and manage promotional coupons and discounts.',
    'customer.view': 'View and manage customer accounts and customer activity.',
    'dodo_team.view': 'View and manage DODO internal team members and assignments.',
    'rbac.manage': 'Manage roles, permissions, and admin user access control.',
    'refund.approve': 'Approve pending refund requests.',
    'refund.policy.manage': 'Manage refund policies and rules.',
    'refund.process': 'Process approved refunds and payment payouts.',
    'refund.review': 'Review submitted refund requests.',
    'refund.view': 'View refund requests, history, and status updates.',
    'service.view': 'View and manage services, attributes, and showcase items.',
    'settings.manage': 'Manage global platform settings, service availability areas, and fees.',
    'vendor.view': 'View and manage vendors, serving areas, tiers, and settlements.',
  };

  factory Permission.fromMap(Map<String, dynamic> map) {
    final nameStr = (map['name'] as String? ?? '').trim();
    final derivedModule = nameStr.contains('.')
        ? nameStr.split('.').first.toUpperCase()
        : 'GENERAL';

    final rawDesc = map['description'] as String?;
    final finalDesc = (rawDesc != null && rawDesc.trim().isNotEmpty)
        ? rawDesc.trim()
        : _defaultDescriptions[nameStr] ?? 'Access permission for $nameStr';

    return Permission(
      id: map['id']?.toString() ?? nameStr,
      name: nameStr,
      description: finalDesc,
      module: derivedModule,
    );
  }
}
