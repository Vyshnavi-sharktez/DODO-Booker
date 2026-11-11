-- Migration: InstaHelp vendor subscription tracking
-- Tracks per-vendor free-order usage for the InstaHelp subscription module.
-- Settings (allowance limits, enforcement flags) live in the generic `settings` table.

CREATE TABLE IF NOT EXISTS vendor_instahelp_free_orders (
  id              UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  vendor_id       UUID         NOT NULL UNIQUE REFERENCES vendors(id) ON DELETE CASCADE,
  orders_used     INT          NOT NULL DEFAULT 0,
  is_restricted   BOOLEAN      NOT NULL DEFAULT false,
  last_reset_at   TIMESTAMPTZ,
  created_at      TIMESTAMPTZ  NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION _set_vendor_instahelp_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

CREATE TRIGGER vendor_instahelp_free_orders_updated_at
  BEFORE UPDATE ON vendor_instahelp_free_orders
  FOR EACH ROW EXECUTE FUNCTION _set_vendor_instahelp_updated_at();

ALTER TABLE vendor_instahelp_free_orders ENABLE ROW LEVEL SECURITY;

CREATE POLICY "admin_all_vendor_instahelp_free_orders"
  ON vendor_instahelp_free_orders FOR ALL
  TO authenticated
  USING (is_active_admin())
  WITH CHECK (is_active_admin());
