-- ── Preferred Vendor Fee ──────────────────────────────────────────────────────
-- Extends the Surge Fee module with a per-vendor opt-in preferred-vendor charge.
--
-- 1. Per-vendor fields on the vendors table.
-- 2. Global enable/disable flag on surge_fee_settings.
-- 3. Booking snapshot columns.
-- 4. RPC for customer checkout: returns preferred vendors serving a coordinate.

-- ── 1. Vendor fields ──────────────────────────────────────────────────────────

ALTER TABLE vendors
  ADD COLUMN IF NOT EXISTS is_preferred_vendor   BOOLEAN      NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS preferred_vendor_fee  NUMERIC(10,2) NOT NULL DEFAULT 0;

-- ── 2. Surge fee settings: preferred vendor fee toggle ────────────────────────

ALTER TABLE surge_fee_settings
  ADD COLUMN IF NOT EXISTS preferred_vendor_fee_enabled BOOLEAN NOT NULL DEFAULT false;

-- ── 3. Booking snapshot columns ───────────────────────────────────────────────

ALTER TABLE bookings
  ADD COLUMN IF NOT EXISTS preferred_vendor_id         UUID,
  ADD COLUMN IF NOT EXISTS preferred_vendor_fee_amount NUMERIC(12,2);

-- ── 4. RPC: preferred vendors whose serving area covers a coordinate ──────────
-- Uses the Haversine formula (same as the admin booking-assignment widget).
-- SECURITY DEFINER so anon role (customer app) can call it without vendor RLS.

CREATE OR REPLACE FUNCTION get_preferred_vendors_for_location(
  p_lat FLOAT8,
  p_lng FLOAT8
)
RETURNS TABLE (
  id                   UUID,
  business_name        TEXT,
  rating               NUMERIC,
  preferred_vendor_fee NUMERIC
)
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT sub.id, sub.business_name, sub.rating, sub.preferred_vendor_fee
  FROM (
    SELECT DISTINCT
      v.id,
      v.business_name,
      v.rating::NUMERIC               AS rating,
      v.preferred_vendor_fee::NUMERIC AS preferred_vendor_fee
    FROM   vendors                        v
    JOIN   vendor_serving_area_assignments vsaa ON vsaa.vendor_id     = v.id
    JOIN   vendor_serving_areas            vsa  ON vsa.id             = vsaa.serving_area_id
    WHERE  v.is_preferred_vendor = true
      AND  v.is_active           = true
      AND  vsa.is_active         = true
      AND  (
        2.0 * 6371.0 * asin(sqrt(
          power(sin(radians((vsa.latitude  - p_lat)  / 2.0)), 2) +
          cos(radians(p_lat)) * cos(radians(vsa.latitude)) *
          power(sin(radians((vsa.longitude - p_lng) / 2.0)), 2)
        ))
      ) <= vsa.radius_km
  ) sub
  ORDER BY sub.rating DESC NULLS LAST, sub.business_name;
$$;
