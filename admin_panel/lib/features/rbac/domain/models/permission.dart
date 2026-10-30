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

  // Merge 'category' and 'service' prefixes into CATALOG so all catalog-related
  // permissions appear under a single module card in the permission selector.
  static const Map<String, String> _moduleAliases = {
    'category': 'CATALOG',
    'service': 'CATALOG',
  };

  static const Map<String, String> _defaultDescriptions = {
    // Legacy coarse permissions
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
    'vendor.view': 'View and manage vendors, service areas, tiers, and settlements.',
    // Granular CRUD permissions
    'booking.create': 'Create bookings manually.',
    'booking.read': 'View bookings, warranty claims, call sessions, and dispatch analytics.',
    'booking.update': 'Edit, reschedule, and assign vendors to bookings.',
    'booking.delete': 'Cancel and delete bookings.',
    'customer.create': 'Create new customer accounts.',
    'customer.read': 'View customer list, profiles, and abandoned carts.',
    'customer.update': 'Edit customer information, addresses, and manage account status.',
    'customer.delete': 'Delete customer accounts.',
    'vendor.create': 'Add new vendor accounts.',
    'vendor.read': 'View vendors, service areas, subscriptions, tiers, and service requests.',
    'vendor.update': 'Edit vendor profiles, verify, assign tiers, and manage settlements.',
    'vendor.delete': 'Delete vendor accounts.',
    'catalog.create': 'Create catalog nodes, categories, services, and AMC plans.',
    'catalog.read': 'View the service catalog, categories, AMC plans, and add-ons.',
    'catalog.update': 'Edit catalog nodes, pricing, attributes, and add-ons.',
    'catalog.delete': 'Delete catalog nodes and service items.',
    'scheduling.create': 'Add calendar overrides and service schedule entries.',
    'scheduling.read': 'View global scheduling, service schedules, and calendar overrides.',
    'scheduling.update': 'Edit scheduling rules and override entries.',
    'scheduling.delete': 'Remove scheduling overrides and service schedule entries.',
    'coupon.create': 'Create promotional coupons.',
    'coupon.read': 'View coupon list and usage statistics.',
    'coupon.update': 'Edit and activate/deactivate coupons.',
    'coupon.delete': 'Delete coupons.',
    'notification.create': 'Create and send broadcast notifications.',
    'notification.read': 'View notification history and broadcast campaigns.',
    'settings.read': 'View platform settings, service areas, fees, SEO, and configuration.',
    'settings.update': 'Edit platform settings, fees, SEO, landing page CMS, and payment config.',
    'rbac.create': 'Create admin roles.',
    'rbac.read': 'View roles, permissions, and admin user assignments.',
    'rbac.update': 'Edit roles, permissions, and admin user role assignments.',
    'rbac.delete': 'Delete roles and remove admin user access.',
    'dodo_team.create': 'Add new DODO field team members.',
    'dodo_team.read': 'View DODO teams and member details.',
    'dodo_team.update': 'Edit DODO team information and assignments.',
    'dodo_team.delete': 'Remove DODO team members.',
    'support.read': 'View support conversations and customer messages.',
    'support.update': 'Reply to and manage support conversations.',
  };

  factory Permission.fromMap(Map<String, dynamic> map) {
    final nameStr = (map['name'] as String? ?? '').trim();
    final prefix = nameStr.contains('.') ? nameStr.split('.').first : nameStr;
    final derivedModule = _moduleAliases[prefix] ?? prefix.toUpperCase();

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
