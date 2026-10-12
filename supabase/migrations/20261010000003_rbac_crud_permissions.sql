-- ─────────────────────────────────────────────────────────────────────────────
-- Granular CRUD Permissions
--
-- Adds fine-grained Create/Read/Update/Delete permissions for every admin
-- module.  Existing coarse permissions (booking.view, settings.manage, etc.)
-- are PRESERVED so that current roles continue to work without any changes.
-- AdminUser.hasPermission in the Flutter app uses a backward-compat map that
-- treats old coarse keys as implying their CRUD equivalents.
-- ─────────────────────────────────────────────────────────────────────────────

INSERT INTO public.permissions (name, description)
SELECT v.name, v.description
FROM (VALUES
  -- Bookings
  ('booking.create',       'Create bookings manually'),
  ('booking.read',         'View bookings, warranty claims, call sessions, and dispatch analytics'),
  ('booking.update',       'Edit, reschedule, and assign vendors to bookings'),
  ('booking.delete',       'Cancel and delete bookings'),
  -- Customers
  ('customer.create',      'Create new customer accounts'),
  ('customer.read',        'View customer list, profiles, and abandoned carts'),
  ('customer.update',      'Edit customer information, addresses, and manage account status'),
  ('customer.delete',      'Delete customer accounts'),
  -- Vendors
  ('vendor.create',        'Add new vendor accounts'),
  ('vendor.read',          'View vendors, serving areas, subscriptions, tiers, and service requests'),
  ('vendor.update',        'Edit vendor profiles, verify, assign tiers, and manage settlements'),
  ('vendor.delete',        'Delete vendor accounts'),
  -- Catalog (categories + sub-categories + services + AMC plans)
  ('catalog.create',       'Create catalog nodes, categories, services, and AMC plans'),
  ('catalog.read',         'View the service catalog, categories, AMC plans, and add-ons'),
  ('catalog.update',       'Edit catalog nodes, pricing, attributes, and add-ons'),
  ('catalog.delete',       'Delete catalog nodes and service items'),
  -- Scheduling
  ('scheduling.create',    'Add calendar overrides and service schedule entries'),
  ('scheduling.read',      'View global scheduling, service schedules, and calendar overrides'),
  ('scheduling.update',    'Edit scheduling rules and override entries'),
  ('scheduling.delete',    'Remove scheduling overrides and service schedule entries'),
  -- Coupons
  ('coupon.create',        'Create promotional coupons'),
  ('coupon.read',          'View coupon list and usage statistics'),
  ('coupon.update',        'Edit and activate/deactivate coupons'),
  ('coupon.delete',        'Delete coupons'),
  -- Notifications
  ('notification.create',  'Create and send broadcast notifications to customers or vendors'),
  ('notification.read',    'View notification history and broadcast campaigns'),
  -- Settings
  ('settings.read',        'View platform settings, service areas, fees, SEO, and configuration'),
  ('settings.update',      'Edit platform settings, fees, SEO, landing page CMS, and payment config'),
  -- RBAC
  ('rbac.create',          'Create admin roles'),
  ('rbac.read',            'View roles, permissions, and admin user assignments'),
  ('rbac.update',          'Edit roles, permissions, and admin user role assignments'),
  ('rbac.delete',          'Delete roles and remove admin user access'),
  -- DODO Teams
  ('dodo_team.create',     'Add new DODO field team members'),
  ('dodo_team.read',       'View DODO teams and member details'),
  ('dodo_team.update',     'Edit DODO team information and assignments'),
  ('dodo_team.delete',     'Remove DODO team members'),
  -- Support
  ('support.read',         'View support conversations and customer messages'),
  ('support.update',       'Reply to and manage support conversations')
) AS v(name, description)
WHERE NOT EXISTS (
  SELECT 1 FROM public.permissions p WHERE p.name = v.name
);
