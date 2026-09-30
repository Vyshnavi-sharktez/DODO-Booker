-- Fix: catalog_node_addons write policies were incorrectly scoped to anon.
-- Admin Panel uses Supabase Auth login → admins are the authenticated role in Postgres,
-- not anon.  The three anon write policies from migration 20260930000003 never matched
-- an authenticated session, causing every INSERT/UPDATE/DELETE from the admin panel to
-- be rejected by RLS even for a Super Admin.
--
-- Customer app reads addons exclusively via resolve_node_addons_batch (SECURITY DEFINER),
-- which bypasses RLS entirely — anon write access is not needed and is removed.
--
-- Pattern follows existing admin-writable tables:
--   service_faqs: "authenticated write"    FOR ALL TO authenticated USING (true)
--   service_add_ons: "authenticated write" FOR ALL TO authenticated USING (true)

-- Drop incorrect anon write policies
DROP POLICY IF EXISTS "anon_insert_catalog_node_addons" ON catalog_node_addons;
DROP POLICY IF EXISTS "anon_update_catalog_node_addons" ON catalog_node_addons;
DROP POLICY IF EXISTS "anon_delete_catalog_node_addons" ON catalog_node_addons;

-- Add authenticated read+write policy (covers admin panel CRUD: assign, unassign, reorder)
CREATE POLICY "authenticated_all_catalog_node_addons"
  ON catalog_node_addons FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- Policies retained from 20260930000003 (correct as-is):
--   "anon_select_catalog_node_addons"         — anon SELECT for direct catalog reads
--   "service_role_all_catalog_node_addons"    — service_role bypass for migrations/triggers
