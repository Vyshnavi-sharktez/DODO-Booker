-- ===========================================================================
-- DODO BOOKER — Test-Data Reset Script
-- Prepared: 2026-10-26
-- ===========================================================================
--
-- WHAT THIS SCRIPT CLEARS
--   Bookings and all FK-dependent transactional data, AMC contracts and
--   visit data, loyalty balances and transactions, notifications,
--   wishlists, carts, support conversations, customer questions,
--   broadcast notifications, and catalog nodes with all dependent
--   configuration tables.
--
-- SAFETY GUARANTEES
--   ✓ No changes to users: customers, vendors, admin_users, auth.users
--   ✓ No changes to RBAC: admin_users (data), admin_user_roles, roles,
--       permissions, role_permissions
--   ✓ No changes to system config: settings, payment_gateway_configs,
--       payment_gateway_secrets, sms_provider_configs, sms_provider_secrets,
--       whatsapp_provider_configs, whatsapp_provider_secrets, tax_settings,
--       loyalty_settings, global_scheduling, commission_rules,
--       dispatch_settings, surge_fee_settings, service_availability_areas,
--       vendor_serving_areas, vendor_serving_area_assignments, vendor_tiers,
--       document_types, refund_issue_categories, refund_policies,
--       subscription_plans, fcm_vault_secrets, seo_global_settings,
--       seo_settings
--   ✓ No changes to CMS/SEO content: cms_pages, landing_page_sections,
--       catalog_node_seo (**SEE NOTE A**), location_node_seo (**SEE NOTE A**)
--   ✓ No sequence resets
--   ✓ Vendor wallets preserved: wallet_transactions, vendor_wallets
--   ✓ Settlement history preserved: vendor_settlements
--   ✓ Subscription payments preserved: vendor_subscription_payments
--   ✓ Vendor subscriptions preserved (catalog_node_id NULLed; rows kept)
--   ✓ Device tokens preserved: device_tokens
--   ✓ Vendor service requests preserved (**SEE NOTE B**)
--
-- NOTE A — catalog_node_seo / location_node_seo:
--   Both tables have ON DELETE CASCADE from catalog_nodes.  Since this
--   script deletes catalog_nodes (Phase 10), those SEO rows will be
--   auto-deleted.  If you want to keep SEO content, you MUST remove
--   the Phase 8 catalog node config section and the Phase 10 catalog_nodes
--   deletion before running.
--
-- NOTE B — vendor_service_requests:
--   These are vendor-submitted custom-service proposals and price-change
--   requests.  They are NOT cleared here because they are vendor-owned
--   records, not test bookings.  booking_items.custom_service_id FK is
--   ON DELETE SET NULL so clearing booking_items first (Phase 2c) removes
--   any reference before this table could block anything.
--
-- CONSTRAINT HANDLING SUMMARY
--   The following RESTRICT / NO ACTION constraints require explicit
--   child-first deletions (confirmed against live DB information_schema):
--     refund_transactions.refund_request_id  → refund_requests   (NO ACTION)
--     refund_requests.booking_id             → bookings          (NO ACTION)
--     vendor_settlement_bookings.booking_id  → bookings          (RESTRICT)
--     customer_reviews.booking_id            → bookings          (NO ACTION)
--     booking_items.booking_id               → bookings          (NO ACTION — live DB differs from migration)
--     booking_images.booking_id              → bookings          (NO ACTION — live DB differs from migration)
--     booking_otp_verifications.booking_id   → bookings          (NO ACTION)
--     booking_status_history.booking_id      → bookings          (NO ACTION)
--     service_attributes.node_id             → catalog_nodes     (NO ACTION)
--     service_attribute_options.attribute_id → service_attributes (NO ACTION)
--     amc_contracts.service_id               → catalog_nodes     (RESTRICT)
--     catalog_nodes.parent_id                → catalog_nodes     (RESTRICT, self-referential)
--     vendor_subscriptions.catalog_node_id   → catalog_nodes     (RESTRICT — NULLed, not deleted)
--     wishlists.node_id                      → catalog_nodes     (NO ACTION — explicit delete in Phase 6)
--
-- HOW TO RUN
--   Paste this script into the Supabase SQL Editor (Dashboard → SQL Editor)
--   and click Run.  The entire script is wrapped in a single transaction;
--   any error rolls back all changes automatically.
--
-- APPROVAL REQUIRED BEFORE RUNNING
--   Review Section "TABLES EXCLUDED — PENDING REVIEW" at the bottom.
-- ===========================================================================


-- ===========================================================================
-- §0  PRE-RESET ROW COUNTS
--     Run these to document the database state before the reset.
--     No changes are made here.
-- ===========================================================================

SELECT 'PRE-RESET COUNTS' AS phase;

SELECT
  'bookings'                   AS tbl, COUNT(*) AS rows FROM bookings
UNION ALL SELECT 'booking_items',                COUNT(*) FROM booking_items
UNION ALL SELECT 'booking_addons',               COUNT(*) FROM booking_addons
UNION ALL SELECT 'booking_images',               COUNT(*) FROM booking_images
UNION ALL SELECT 'booking_payments',             COUNT(*) FROM booking_payments
UNION ALL SELECT 'booking_assignments',          COUNT(*) FROM booking_assignments
UNION ALL SELECT 'vendor_settlement_bookings',   COUNT(*) FROM vendor_settlement_bookings
UNION ALL SELECT 'customer_reviews',             COUNT(*) FROM customer_reviews
UNION ALL SELECT 'refund_requests',              COUNT(*) FROM refund_requests
UNION ALL SELECT 'refund_transactions',          COUNT(*) FROM refund_transactions
UNION ALL SELECT 'refund_status_history',        COUNT(*) FROM refund_status_history
UNION ALL SELECT 'refund_messages',              COUNT(*) FROM refund_messages
UNION ALL SELECT 'service_warranties',           COUNT(*) FROM service_warranties
UNION ALL SELECT 'call_sessions',                COUNT(*) FROM call_sessions
UNION ALL SELECT 'gps_cancellation_audits',      COUNT(*) FROM gps_cancellation_audits
UNION ALL SELECT 'vendor_location_logs',         COUNT(*) FROM vendor_location_logs
UNION ALL SELECT 'deleted_bookings',             COUNT(*) FROM deleted_bookings
UNION ALL SELECT 'amc_contracts',                COUNT(*) FROM amc_contracts
UNION ALL SELECT 'amc_scheduling_requests',      COUNT(*) FROM amc_scheduling_requests
UNION ALL SELECT 'amc_pause_requests',           COUNT(*) FROM amc_pause_requests
UNION ALL SELECT 'amc_resume_requests',          COUNT(*) FROM amc_resume_requests
UNION ALL SELECT 'amc_cancellation_requests',    COUNT(*) FROM amc_cancellation_requests
UNION ALL SELECT 'loyalty_transactions',         COUNT(*) FROM loyalty_transactions
UNION ALL SELECT 'customer_loyalty',             COUNT(*) FROM customer_loyalty
UNION ALL SELECT 'notifications',                COUNT(*) FROM notifications
UNION ALL SELECT 'push_deliveries',              COUNT(*) FROM push_deliveries
UNION ALL SELECT 'wishlists',                    COUNT(*) FROM wishlists
UNION ALL SELECT 'cart_items',                   COUNT(*) FROM cart_items
UNION ALL SELECT 'support_conversations',        COUNT(*) FROM support_conversations
UNION ALL SELECT 'support_messages',             COUNT(*) FROM support_messages
UNION ALL SELECT 'support_reminder_logs',        COUNT(*) FROM support_reminder_logs
UNION ALL SELECT 'customer_questions',           COUNT(*) FROM customer_questions
UNION ALL SELECT 'broadcast_notifications',      COUNT(*) FROM broadcast_notifications
UNION ALL SELECT 'catalog_nodes',                COUNT(*) FROM catalog_nodes
UNION ALL SELECT 'catalog_node_relationships',   COUNT(*) FROM catalog_node_relationships
UNION ALL SELECT 'catalog_node_configs',         COUNT(*) FROM catalog_node_configs
UNION ALL SELECT 'catalog_node_addons',          COUNT(*) FROM catalog_node_addons
UNION ALL SELECT 'catalog_node_amc_plans',       COUNT(*) FROM catalog_node_amc_plans
UNION ALL SELECT 'catalog_node_location_restrictions', COUNT(*) FROM catalog_node_location_restrictions
UNION ALL SELECT 'catalog_node_seo',             COUNT(*) FROM catalog_node_seo
UNION ALL SELECT 'location_node_seo',            COUNT(*) FROM location_node_seo
UNION ALL SELECT 'service_attribute_options',    COUNT(*) FROM service_attribute_options
UNION ALL SELECT 'service_attributes',           COUNT(*) FROM service_attributes
UNION ALL SELECT 'service_faqs',                 COUNT(*) FROM service_faqs
UNION ALL SELECT 'service_showcase_images',      COUNT(*) FROM service_showcase_images
UNION ALL SELECT 'service_scheduling',           COUNT(*) FROM service_scheduling
UNION ALL SELECT 'service_packages',             COUNT(*) FROM service_packages
UNION ALL SELECT 'package_services',             COUNT(*) FROM package_services
UNION ALL SELECT 'calendar_schedules',           COUNT(*) FROM calendar_schedules
UNION ALL SELECT 'availability_blocks',          COUNT(*) FROM availability_blocks
UNION ALL SELECT 'booking_images',               COUNT(*) FROM booking_images
UNION ALL SELECT 'booking_otp_verifications',    COUNT(*) FROM booking_otp_verifications
UNION ALL SELECT 'booking_status_history',       COUNT(*) FROM booking_status_history
UNION ALL SELECT 'booking_attribute_selections', COUNT(*) FROM booking_attribute_selections
UNION ALL SELECT 'addons',                       COUNT(*) FROM addons
UNION ALL SELECT 'amc_plans',                    COUNT(*) FROM amc_plans
UNION ALL SELECT 'coupons (used_count > 0)',     COUNT(*) FROM coupons WHERE used_count > 0
ORDER BY tbl;


-- ===========================================================================
-- §1  BEGIN TRANSACTION
-- ===========================================================================

BEGIN;


-- ===========================================================================
-- §2  PHASE 1 — REFUND DATA
--
-- refund_transactions has a NO ACTION FK to refund_requests.
-- refund_requests has a NO ACTION FK to bookings.
-- Both must be deleted before bookings can be removed.
--
-- Cascades that happen automatically when refund_requests is deleted:
--   • refund_status_history  (ON DELETE CASCADE from refund_requests)
--   • refund_messages        (ON DELETE CASCADE from refund_requests)
-- ===========================================================================

SELECT 'Phase 1: Refund data' AS phase;

-- 1a. refund_transactions: NO ACTION FK to refund_requests
DELETE FROM refund_transactions;

-- 1b. refund_requests: NO ACTION FK to bookings
--     Auto-cascades: refund_status_history, refund_messages
DELETE FROM refund_requests;


-- ===========================================================================
-- §3  PHASE 2 — BOOKING DEPENDENTS WITH RESTRICT / NO ACTION FKs
--
-- Live DB information_schema confirms these tables have NO ACTION or RESTRICT
-- FK to bookings and therefore must be deleted before bookings.
-- (Several differ from what the CREATE TABLE migrations specified — the live
--  constraints from the base schema take precedence.)
-- ===========================================================================

SELECT 'Phase 2: Booking dependents (RESTRICT / NO ACTION)' AS phase;

-- 2a. vendor_settlement_bookings: RESTRICT FK to bookings.
--     vendor_settlements rows are PRESERVED (financial history).
--     Only the booking→settlement junction rows are removed.
DELETE FROM vendor_settlement_bookings;

-- 2b. customer_reviews: NO ACTION FK to bookings.
DELETE FROM customer_reviews;

-- 2c. booking_items: NO ACTION FK to bookings (confirmed live).
--     booking_items.service_id and catalog_parent_node_id → catalog_nodes
--     are ON DELETE SET NULL, so catalog_nodes deletion in Phase 10 is safe.
DELETE FROM booking_items;

-- 2d. booking_images: NO ACTION FK to bookings (live DB; migration said CASCADE).
DELETE FROM booking_images;

-- 2e. booking_otp_verifications: NO ACTION FK to bookings.
DELETE FROM booking_otp_verifications;

-- 2f. booking_status_history: NO ACTION FK to bookings.
DELETE FROM booking_status_history;

-- 2g. booking_attribute_selections: no FK to bookings in live DB
--     (dropped by retarget migration), but booking-coupled test data.
DELETE FROM booking_attribute_selections;


-- ===========================================================================
-- §4  PHASE 3 — BOOKINGS
--
-- Deleting bookings triggers the following automatic cascades
-- (confirmed against live information_schema delete_rule = CASCADE):
--   • booking_addons          (CASCADE)
--   • booking_assignments     (CASCADE)
--   • booking_payments        (CASCADE)
--   • call_sessions           (CASCADE)
--   • gps_cancellation_audits (CASCADE)
--   • service_warranties      (booking_id, CASCADE)
--   • vendor_location_logs    (CASCADE)
-- And the following SET NULLs:
--   • amc_cancellation_requests.booking_id (SET NULL)
--   • amc_scheduling_requests.booking_id   (SET NULL)
--   • loyalty_transactions.booking_id      (SET NULL)
--   • service_warranties.rework_booking_id (SET NULL)
-- (booking_images, booking_items, booking_otp_verifications,
--  booking_status_history were already deleted in Phase 2.)
-- ===========================================================================

SELECT 'Phase 3: Bookings (cascade children)' AS phase;

-- 3a. bookings: parent of all booking-dependent transactional tables.
DELETE FROM bookings;

-- 3b. deleted_bookings: JSONB archive of admin-deleted bookings.
--     deleted_by → auth.users is ON DELETE SET NULL (no blocker).
DELETE FROM deleted_bookings;


-- ===========================================================================
-- §5  PHASE 4 — AMC CONTRACTS AND REQUESTS
--
-- amc_contracts.service_id has a RESTRICT FK to catalog_nodes, so
-- contracts must be deleted BEFORE catalog_nodes (Phase 10).
--
-- bookings.amc_contract_id was SET NULL in Phase 3, so no bookings
-- now reference these contracts.
--
-- Cascades when amc_contracts is deleted:
--   • amc_scheduling_requests  (ON DELETE CASCADE, booking_id is already NULL)
--   • amc_pause_requests       (ON DELETE CASCADE)
--   • amc_resume_requests      (ON DELETE CASCADE)
--   • amc_cancellation_requests (ON DELETE CASCADE)
-- ===========================================================================

SELECT 'Phase 4: AMC contracts and requests' AS phase;

-- 4a-d. Explicit deletes for clarity (would auto-cascade in 4e, but
--       explicit deletes make the script easier to audit).
DELETE FROM amc_cancellation_requests;
DELETE FROM amc_scheduling_requests;
DELETE FROM amc_pause_requests;
DELETE FROM amc_resume_requests;

-- 4e. amc_contracts: RESTRICT FK to catalog_nodes cleared here.
DELETE FROM amc_contracts;


-- ===========================================================================
-- §6  PHASE 5 — LOYALTY DATA
--
-- loyalty_transactions.booking_id was SET NULL in Phase 3.
-- loyalty_transactions.customer_id → customers is ON DELETE CASCADE
-- from customers, but customers are PRESERVED — so we delete explicitly.
-- customer_loyalty.customer_id → customers is likewise ON DELETE CASCADE;
-- rows deleted explicitly here to zero all test balances.
-- ===========================================================================

SELECT 'Phase 5: Loyalty data' AS phase;

DELETE FROM loyalty_transactions;
DELETE FROM customer_loyalty;


-- ===========================================================================
-- §7  PHASE 6 — TRANSACTIONAL USER STATE
--
-- Notifications, wishlists, carts, support chat, customer questions,
-- and broadcast campaigns are all transactional records that should be
-- cleared for a clean test-data reset.
-- ===========================================================================

SELECT 'Phase 6: Transactional user state' AS phase;

-- 6a. push_deliveries: ON DELETE CASCADE from notifications.
--     Deleted explicitly before notifications so the intent is clear.
DELETE FROM push_deliveries;

-- 6b. notifications: in-app and push notification rows for customers/vendors.
--     parent_node_id → catalog_nodes is ON DELETE SET NULL (no blocker
--     in Phase 10 even if notifications existed, but they won't after this).
DELETE FROM notifications;

-- 6c. wishlists: ON DELETE CASCADE from both customers and catalog_nodes.
--     Deleted explicitly; catalog_nodes CASCADE in Phase 10 would handle
--     it automatically, but explicit is cleaner.
DELETE FROM wishlists;

-- 6d. cart_items: customer cart state.
--     parent_node_id → catalog_nodes is ON DELETE SET NULL.
DELETE FROM cart_items;

-- 6e-g. Support chat: support_messages and support_reminder_logs both
--       have ON DELETE CASCADE from support_conversations.
DELETE FROM support_reminder_logs;
DELETE FROM support_messages;
DELETE FROM support_conversations;

-- 6h. customer_questions: ON DELETE CASCADE from catalog_nodes and customers.
--     parent_node_id → catalog_nodes is ON DELETE SET NULL.
DELETE FROM customer_questions;

-- 6i. broadcast_notifications: admin-created notification campaigns.
--     created_by → admin_users is ON DELETE SET NULL (admins preserved).
DELETE FROM broadcast_notifications;


-- ===========================================================================
-- §8  PHASE 7 — NULL OUT vendor_subscriptions.catalog_node_id
--
-- vendor_subscriptions.catalog_node_id has a RESTRICT FK to catalog_nodes.
-- Vendor subscription RECORDS are financial data and are PRESERVED.
-- Only the catalog_node_id pointer is NULLed so Phase 10 can proceed.
--
-- After this UPDATE:
--   • Subscription records still exist with all financial data intact.
--   • The FK to the soon-to-be-deleted catalog node is removed.
--   • subscription_permissions snapshot is preserved on the row.
-- ===========================================================================

SELECT 'Phase 7: NULL out vendor_subscriptions.catalog_node_id (RESTRICT blocker)' AS phase;

UPDATE vendor_subscriptions
   SET catalog_node_id = NULL
 WHERE catalog_node_id IS NOT NULL;


-- ===========================================================================
-- §9  PHASE 8 — CATALOG NODE CONFIGURATION
--
-- All these tables have ON DELETE CASCADE from catalog_nodes, so they
-- would be auto-deleted in Phase 10.  They are deleted explicitly here
-- to make the script self-documenting and to confirm intent.
--
-- WARNING: catalog_node_seo and location_node_seo store SEO content.
-- Deleting catalog_nodes (Phase 10) will auto-cascade these regardless.
-- See NOTE A at the top of this script.
-- ===========================================================================

SELECT 'Phase 8: Catalog node configuration' AS phase;

-- Junction table: catalog_nodes ↔ addons (both sides CASCADE)
DELETE FROM catalog_node_addons;

-- Junction table: catalog_nodes ↔ amc_plans (both sides CASCADE)
DELETE FROM catalog_node_amc_plans;

-- Per-node showcase images
DELETE FROM service_showcase_images;

-- Slot-pause blocks (global/category/service/vendor scopes; node_id CASCADE)
DELETE FROM availability_blocks;

-- Per-node location-based availability rules
DELETE FROM catalog_node_location_restrictions;

-- Module configs (tax, loyalty, scheduling, commission) scoped to nodes or relationships.
-- relationship_id → catalog_node_relationships CASCADE; node_id → catalog_nodes CASCADE.
-- Delete catalog_node_relationships first to avoid orphaned relationship-scoped rows.
DELETE FROM catalog_node_configs;
DELETE FROM catalog_node_relationships;

-- SEO metadata rows (see NOTE A — these cascade from catalog_nodes anyway)
DELETE FROM catalog_node_seo;
DELETE FROM location_node_seo;

-- Per-node FAQs (service_id → catalog_nodes ON DELETE CASCADE)
DELETE FROM service_faqs;

-- Per-node scheduling slot definitions (service_id → catalog_nodes CASCADE)
DELETE FROM service_scheduling;

-- Calendar-based scheduling blocks (service_id → catalog_nodes CASCADE)
DELETE FROM calendar_schedules;

-- Service attribute options: NO ACTION FK to service_attributes.
-- Must be deleted BEFORE service_attributes.
DELETE FROM service_attribute_options;

-- Service attributes: node_id → catalog_nodes ON DELETE NO ACTION (confirmed live).
-- Must be deleted BEFORE catalog_nodes.  Also has service_id CASCADE, but
-- the NO ACTION on node_id is the binding constraint.
DELETE FROM service_attributes;

-- Service packages and package_services (service_id → catalog_nodes CASCADE).
-- Catalog config; auto-cascade in Phase 10 but explicit here for auditability.
DELETE FROM package_services;
DELETE FROM service_packages;

-- Add-on product catalogue: name, price, description entries.
-- booking_addons.addon_id → addons was RESTRICT but booking_addons were
-- already deleted in Phase 3 (CASCADE from bookings).
-- catalog_node_addons.addon_id → addons was CASCADE-deleted above.
DELETE FROM addons;


-- ===========================================================================
-- §10  PHASE 9 — AMC PLANS (catalog config)
--
-- amc_plans is catalog configuration: plan definitions attached to catalog
-- nodes.  All referencing rows have been cleared:
--   • catalog_node_amc_plans deleted in Phase 8
--   • amc_contracts.amc_plan_id → amc_plans is ON DELETE SET NULL,
--     and amc_contracts were deleted in Phase 4
-- ===========================================================================

SELECT 'Phase 9: AMC plans' AS phase;

DELETE FROM amc_plans;


-- ===========================================================================
-- §11  PHASE 10 — CATALOG NODES
--
-- catalog_nodes.parent_id is a SELF-REFERENTIAL FK with ON DELETE RESTRICT.
-- Attempting to delete a parent node while its children still exist will
-- fail.  Solution: NULL out parent_id first, removing all RESTRICT
-- constraints, then delete all nodes in a single statement.
--
-- After the UPDATE, any remaining dependent tables with ON DELETE CASCADE
-- (service_faqs, service_add_ons, service_scheduling, etc.) will auto-
-- cascade.  All were explicitly deleted in Phase 8 so the cascade is a
-- no-op safety net.
-- ===========================================================================

SELECT 'Phase 10: Catalog nodes' AS phase;

-- 10a. parent_id was dropped in migration 20260714000007_drop_parent_id_column.sql;
--      hierarchy is now managed entirely by catalog_node_relationships (deleted
--      in Phase 8).  No self-referential FK exists — direct deletion is safe.

-- 10b. Delete all catalog nodes.
--      Remaining cascade targets (should all be empty from Phase 8):
--        service_faqs, service_add_ons, service_showcase_images,
--        catalog_node_addons, catalog_node_amc_plans,
--        catalog_node_location_restrictions, catalog_node_configs,
--        catalog_node_relationships, catalog_node_seo, location_node_seo,
--        service_scheduling, calendar_schedules, availability_blocks
--      SET NULL targets:
--        wishlists.service_id (empty from Phase 6)
--        cart_items.service_id (empty from Phase 6)
--        booking_items.service_id (empty from Phase 2)
--        notifications.parent_node_id (empty from Phase 6)
--        customer_questions.parent_node_id (empty from Phase 6)
--        amc_plans.service_id (if any remain — Phase 9 cleared them)
--      RESTRICT blocker:
--        vendor_subscriptions.catalog_node_id — NULLed in Phase 7
DELETE FROM catalog_nodes;


-- ===========================================================================
-- §12  PHASE 11 — COUPON USAGE COUNTERS
--
-- Coupons are admin-configured promotions (NOT test data) and are
-- PRESERVED.  Only the per-booking usage counter is reset to zero so
-- coupon limits function correctly against a clean booking slate.
-- ===========================================================================

SELECT 'Phase 11: Coupon usage counters' AS phase;

UPDATE coupons SET used_count = 0 WHERE used_count > 0;


-- ===========================================================================
-- §13  COMMIT
-- ===========================================================================

COMMIT;


-- ===========================================================================
-- §14  POST-RESET VERIFICATION COUNTS
--     Run after COMMIT to confirm all target tables are empty / zeroed.
--     All rows-remaining values should be 0 (or 0 for coupon used_count).
-- ===========================================================================

SELECT 'POST-RESET VERIFICATION' AS phase;

SELECT
  'bookings'                   AS tbl, COUNT(*) AS rows_remaining FROM bookings
UNION ALL SELECT 'booking_items',                COUNT(*) FROM booking_items
UNION ALL SELECT 'booking_addons',               COUNT(*) FROM booking_addons
UNION ALL SELECT 'booking_images',               COUNT(*) FROM booking_images
UNION ALL SELECT 'booking_payments',             COUNT(*) FROM booking_payments
UNION ALL SELECT 'booking_assignments',          COUNT(*) FROM booking_assignments
UNION ALL SELECT 'vendor_settlement_bookings',   COUNT(*) FROM vendor_settlement_bookings
UNION ALL SELECT 'customer_reviews',             COUNT(*) FROM customer_reviews
UNION ALL SELECT 'refund_requests',              COUNT(*) FROM refund_requests
UNION ALL SELECT 'refund_transactions',          COUNT(*) FROM refund_transactions
UNION ALL SELECT 'refund_status_history',        COUNT(*) FROM refund_status_history
UNION ALL SELECT 'refund_messages',              COUNT(*) FROM refund_messages
UNION ALL SELECT 'service_warranties',           COUNT(*) FROM service_warranties
UNION ALL SELECT 'call_sessions',                COUNT(*) FROM call_sessions
UNION ALL SELECT 'gps_cancellation_audits',      COUNT(*) FROM gps_cancellation_audits
UNION ALL SELECT 'vendor_location_logs',         COUNT(*) FROM vendor_location_logs
UNION ALL SELECT 'deleted_bookings',             COUNT(*) FROM deleted_bookings
UNION ALL SELECT 'amc_contracts',                COUNT(*) FROM amc_contracts
UNION ALL SELECT 'amc_scheduling_requests',      COUNT(*) FROM amc_scheduling_requests
UNION ALL SELECT 'amc_pause_requests',           COUNT(*) FROM amc_pause_requests
UNION ALL SELECT 'amc_resume_requests',          COUNT(*) FROM amc_resume_requests
UNION ALL SELECT 'amc_cancellation_requests',    COUNT(*) FROM amc_cancellation_requests
UNION ALL SELECT 'loyalty_transactions',         COUNT(*) FROM loyalty_transactions
UNION ALL SELECT 'customer_loyalty',             COUNT(*) FROM customer_loyalty
UNION ALL SELECT 'notifications',                COUNT(*) FROM notifications
UNION ALL SELECT 'push_deliveries',              COUNT(*) FROM push_deliveries
UNION ALL SELECT 'wishlists',                    COUNT(*) FROM wishlists
UNION ALL SELECT 'cart_items',                   COUNT(*) FROM cart_items
UNION ALL SELECT 'support_conversations',        COUNT(*) FROM support_conversations
UNION ALL SELECT 'support_messages',             COUNT(*) FROM support_messages
UNION ALL SELECT 'support_reminder_logs',        COUNT(*) FROM support_reminder_logs
UNION ALL SELECT 'customer_questions',           COUNT(*) FROM customer_questions
UNION ALL SELECT 'broadcast_notifications',      COUNT(*) FROM broadcast_notifications
UNION ALL SELECT 'catalog_nodes',                COUNT(*) FROM catalog_nodes
UNION ALL SELECT 'catalog_node_relationships',   COUNT(*) FROM catalog_node_relationships
UNION ALL SELECT 'catalog_node_configs',         COUNT(*) FROM catalog_node_configs
UNION ALL SELECT 'catalog_node_addons',          COUNT(*) FROM catalog_node_addons
UNION ALL SELECT 'catalog_node_amc_plans',       COUNT(*) FROM catalog_node_amc_plans
UNION ALL SELECT 'catalog_node_location_restrictions', COUNT(*) FROM catalog_node_location_restrictions
UNION ALL SELECT 'catalog_node_seo',             COUNT(*) FROM catalog_node_seo
UNION ALL SELECT 'location_node_seo',            COUNT(*) FROM location_node_seo
UNION ALL SELECT 'service_attribute_options',    COUNT(*) FROM service_attribute_options
UNION ALL SELECT 'service_attributes',           COUNT(*) FROM service_attributes
UNION ALL SELECT 'service_faqs',                 COUNT(*) FROM service_faqs
UNION ALL SELECT 'service_showcase_images',      COUNT(*) FROM service_showcase_images
UNION ALL SELECT 'service_scheduling',           COUNT(*) FROM service_scheduling
UNION ALL SELECT 'service_packages',             COUNT(*) FROM service_packages
UNION ALL SELECT 'package_services',             COUNT(*) FROM package_services
UNION ALL SELECT 'calendar_schedules',           COUNT(*) FROM calendar_schedules
UNION ALL SELECT 'availability_blocks',          COUNT(*) FROM availability_blocks
UNION ALL SELECT 'booking_images',               COUNT(*) FROM booking_images
UNION ALL SELECT 'booking_otp_verifications',    COUNT(*) FROM booking_otp_verifications
UNION ALL SELECT 'booking_status_history',       COUNT(*) FROM booking_status_history
UNION ALL SELECT 'booking_attribute_selections', COUNT(*) FROM booking_attribute_selections
UNION ALL SELECT 'addons',                       COUNT(*) FROM addons
UNION ALL SELECT 'amc_plans',                    COUNT(*) FROM amc_plans
UNION ALL SELECT 'coupons (used_count > 0)',     COUNT(*) FROM coupons WHERE used_count > 0
ORDER BY tbl;

-- Spot-check: preserved tables should be UNCHANGED from pre-reset counts.
SELECT 'PRESERVED — spot check' AS phase;

SELECT
  'vendor_settlements'         AS tbl, COUNT(*) AS rows FROM vendor_settlements
UNION ALL SELECT 'wallet_transactions',          COUNT(*) FROM wallet_transactions
UNION ALL SELECT 'vendor_subscriptions',         COUNT(*) FROM vendor_subscriptions
UNION ALL SELECT 'vendor_subscription_payments', COUNT(*) FROM vendor_subscription_payments
UNION ALL SELECT 'customers',                    COUNT(*) FROM customers
UNION ALL SELECT 'vendors',                      COUNT(*) FROM vendors
UNION ALL SELECT 'admin_users',                  COUNT(*) FROM admin_users
UNION ALL SELECT 'subscription_plans',           COUNT(*) FROM subscription_plans
UNION ALL SELECT 'device_tokens',                COUNT(*) FROM device_tokens
UNION ALL SELECT 'coupons (total)',              COUNT(*) FROM coupons
UNION ALL SELECT 'vendor_service_requests',      COUNT(*) FROM vendor_service_requests
ORDER BY tbl;


-- ===========================================================================
-- TABLES EXCLUDED — PENDING REVIEW
-- ===========================================================================
-- The following tables were examined and excluded.  Confirm before each run:
--
-- 1. vendor_settlements
--    Financial settlement batches paid to vendors.  Contains real monetary
--    records.  EXCLUDED — do NOT delete without explicit sign-off.
--
-- 2. wallet_transactions
--    Vendor wallet audit log (top-ups, commissions, penalties, adjustments).
--    EXCLUDED — financial record, part of the prepaid security wallet.
--
-- 3. vendor_subscriptions
--    Subscription agreements between vendors and DODO.  catalog_node_id is
--    NULLed in Phase 7 to unblock catalog_nodes deletion but the subscription
--    rows are PRESERVED.  If you want to also clear these, add:
--      DELETE FROM vendor_subscription_payments;
--      DELETE FROM vendor_subscriptions;
--    BEFORE Phase 7 (Phase 7 UPDATE becomes unnecessary then).
--
-- 4. vendor_subscription_payments
--    Payment records for subscription invoices.  Financial data.
--    EXCLUDED.
--
-- 5. device_tokens
--    FCM/APNs push tokens per user device.  These are user-owned session
--    state, not test data.  Clearing them would break push notifications
--    until users reopen the app.  EXCLUDED.
--
-- 6. vendor_service_requests
--    Vendor-submitted custom-service proposals and price-change requests.
--    These survive across test resets (they represent vendor business data,
--    not booking data).  booking_items.custom_service_id is ON DELETE SET NULL,
--    so clearing bookings does not require touching this table.
--    EXCLUDED — review if a full vendor data wipe is also desired.
--
-- 7. coupon_customer_restrictions
--    Admin-configured allowlists for 'selected' eligibility coupons.
--    These are intentional admin-set restrictions, not test-booking state.
--    EXCLUDED — only coupon.used_count (booking counter) is reset.
--
-- 8. catalog_node_seo / location_node_seo
--    SEO page content generated for catalog nodes.  Will be auto-deleted
--    in Phase 10 via ON DELETE CASCADE from catalog_nodes.
--    If you want to preserve this SEO content, skip Phase 8 (catalog
--    config) and Phase 10 (catalog_nodes deletion) entirely.
-- ===========================================================================
