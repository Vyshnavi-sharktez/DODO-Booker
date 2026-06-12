// RBAC foundation — roles and permissions are defined here.
// Enforcement logic belongs in vendor-auth branch, not here.

enum VendorRole {
  owner,
  manager,
  staff;

  String get label => switch (this) {
        VendorRole.owner => 'Owner',
        VendorRole.manager => 'Manager',
        VendorRole.staff => 'Staff',
      };
}

enum VendorPermission {
  // Dashboard
  viewDashboard,

  // Bookings
  viewBookings,
  manageBookings,

  // Services
  viewServices,
  manageServices,

  // Wallet
  viewWallet,
  manageWallet,

  // Notifications
  viewNotifications,

  // Profile & Settings
  manageProfile,
  manageSettings,
}

// Default permission sets per role.
// Enforcement is added in vendor-auth — this is the source-of-truth declaration.
const Map<VendorRole, Set<VendorPermission>> kDefaultRolePermissions = {
  VendorRole.owner: {
    VendorPermission.viewDashboard,
    VendorPermission.viewBookings,
    VendorPermission.manageBookings,
    VendorPermission.viewServices,
    VendorPermission.manageServices,
    VendorPermission.viewWallet,
    VendorPermission.manageWallet,
    VendorPermission.viewNotifications,
    VendorPermission.manageProfile,
    VendorPermission.manageSettings,
  },
  VendorRole.manager: {
    VendorPermission.viewDashboard,
    VendorPermission.viewBookings,
    VendorPermission.manageBookings,
    VendorPermission.viewServices,
    VendorPermission.viewWallet,
    VendorPermission.viewNotifications,
    VendorPermission.manageProfile,
  },
  VendorRole.staff: {
    VendorPermission.viewDashboard,
    VendorPermission.viewBookings,
    VendorPermission.viewNotifications,
  },
};

extension VendorRoleX on VendorRole {
  bool hasPermission(VendorPermission permission) =>
      kDefaultRolePermissions[this]?.contains(permission) ?? false;
}
