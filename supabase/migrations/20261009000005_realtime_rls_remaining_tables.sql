-- Enable RLS on all remaining tables that have Supabase Realtime subscriptions.
--
-- Root cause (same as 20260928000002 for notifications and 20261009000004 for
-- bookings): Supabase Realtime v2.9+ silently drops postgres_changes events for
-- tables where RLS is NOT enabled. A single permissive ALL policy replicates the
-- previous no-RLS behaviour exactly. Security is enforced at the app layer.
--
-- Affected subscriptions (app → table):
--   admin  → customer_reviews, vendor_settlements, vendor_settlement_bookings, customers
--   customer → banners
--   vendor   → vendor_wallets, vendor_documents

-- ── customer_reviews ──────────────────────────────────────────────────────────
ALTER TABLE public.customer_reviews ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow all access customer_reviews" ON public.customer_reviews;
CREATE POLICY "Allow all access customer_reviews"
  ON public.customer_reviews FOR ALL
  TO anon, authenticated, service_role
  USING (true) WITH CHECK (true);

-- ── vendor_settlements ────────────────────────────────────────────────────────
ALTER TABLE public.vendor_settlements ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow all access vendor_settlements" ON public.vendor_settlements;
CREATE POLICY "Allow all access vendor_settlements"
  ON public.vendor_settlements FOR ALL
  TO anon, authenticated, service_role
  USING (true) WITH CHECK (true);

-- ── vendor_settlement_bookings ────────────────────────────────────────────────
ALTER TABLE public.vendor_settlement_bookings ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow all access vendor_settlement_bookings" ON public.vendor_settlement_bookings;
CREATE POLICY "Allow all access vendor_settlement_bookings"
  ON public.vendor_settlement_bookings FOR ALL
  TO anon, authenticated, service_role
  USING (true) WITH CHECK (true);

-- ── customers ─────────────────────────────────────────────────────────────────
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow all access customers" ON public.customers;
CREATE POLICY "Allow all access customers"
  ON public.customers FOR ALL
  TO anon, authenticated, service_role
  USING (true) WITH CHECK (true);

-- ── banners ───────────────────────────────────────────────────────────────────
ALTER TABLE public.banners ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow all access banners" ON public.banners;
CREATE POLICY "Allow all access banners"
  ON public.banners FOR ALL
  TO anon, authenticated, service_role
  USING (true) WITH CHECK (true);

-- ── vendor_wallets ────────────────────────────────────────────────────────────
ALTER TABLE public.vendor_wallets ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow all access vendor_wallets" ON public.vendor_wallets;
CREATE POLICY "Allow all access vendor_wallets"
  ON public.vendor_wallets FOR ALL
  TO anon, authenticated, service_role
  USING (true) WITH CHECK (true);

-- ── vendor_documents ─────────────────────────────────────────────────────────
ALTER TABLE public.vendor_documents ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow all access vendor_documents" ON public.vendor_documents;
CREATE POLICY "Allow all access vendor_documents"
  ON public.vendor_documents FOR ALL
  TO anon, authenticated, service_role
  USING (true) WITH CHECK (true);
