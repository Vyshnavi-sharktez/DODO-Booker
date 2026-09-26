-- ─────────────────────────────────────────────────────────────────────────────
-- Seed Base Permissions
--
-- Seeds all permissions that are referenced in the Flutter admin panel but
-- were previously created only via Supabase Studio (not via migrations).
--
-- Refund permissions (refund.*) are intentionally omitted here — they were
-- already seeded by migration 20260922000011_seed_refund_permissions.sql.
--
-- Each INSERT uses the same filtered-INSERT pattern from 20260922000011:
-- insert only when a row with that name does not already exist.  This is
-- idempotent without requiring a UNIQUE constraint on permissions.name.
-- ─────────────────────────────────────────────────────────────────────────────

INSERT INTO public.permissions (name, description)
SELECT v.name, v.description
FROM (VALUES
  ('rbac.manage',      'Manage admin users, roles, and permission assignments'),
  ('category.view',    'View and manage service categories, sub-categories, catalog nodes, AMC plans, and add-ons'),
  ('service.view',     'View and manage services and service attributes'),
  ('vendor.view',      'View and manage vendors, serving areas, settlements, subscriptions, tiers, and service requests'),
  ('dodo_team.view',   'View and manage DODO field teams'),
  ('booking.view',     'View and manage bookings, warranty claims, call sessions, dispatch analytics, GPS audit, AMC scheduling, and support'),
  ('customer.view',    'View and manage customers and abandoned carts'),
  ('coupon.view',      'View and manage promotional coupons'),
  ('settings.manage',  'Manage platform settings, scheduling, tax, commission, surge fees, SEO, landing page CMS, payment config, and service areas')
) AS v(name, description)
WHERE NOT EXISTS (
  SELECT 1 FROM public.permissions p WHERE p.name = v.name
);
