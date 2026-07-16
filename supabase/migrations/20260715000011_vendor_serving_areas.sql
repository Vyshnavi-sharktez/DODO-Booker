-- vendor_serving_areas: Admin-controlled geographic serving zones.
--
-- Admins create named zones with a lat/lng center and radius_km.
-- Vendors select from active zones during registration/profile setup.
-- The lat/lng + radius_km design enables future Haversine-based
-- customer-address → vendor-zone matching.
--
-- The old vendor_service_areas table (vendor-owned, text-based) is NOT
-- dropped. Existing data is preserved for backward compatibility.

-- ── Master zone list (admin-controlled) ──────────────────────────────────────

CREATE TABLE vendor_serving_areas (
  id          UUID           PRIMARY KEY DEFAULT gen_random_uuid(),
  name        TEXT           NOT NULL,
  city        TEXT           NOT NULL,
  latitude    NUMERIC(10, 7) NOT NULL,
  longitude   NUMERIC(10, 7) NOT NULL,
  radius_km   NUMERIC(6, 2)  NOT NULL DEFAULT 5.0,
  is_active   BOOLEAN        NOT NULL DEFAULT true,
  created_at  TIMESTAMPTZ    NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ    NOT NULL DEFAULT now()
);

-- ── Vendor selections (references master list) ────────────────────────────────
--
-- ON DELETE RESTRICT on serving_area_id prevents deletion of a zone that
-- still has vendor assignments.  Admin must unassign all vendors first.

CREATE TABLE vendor_serving_area_assignments (
  id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  vendor_id       UUID        NOT NULL REFERENCES vendors(id)               ON DELETE CASCADE,
  serving_area_id UUID        NOT NULL REFERENCES vendor_serving_areas(id)  ON DELETE RESTRICT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (vendor_id, serving_area_id)
);

CREATE INDEX idx_vsaa_vendor       ON vendor_serving_area_assignments (vendor_id);
CREATE INDEX idx_vsaa_serving_area ON vendor_serving_area_assignments (serving_area_id);
CREATE INDEX idx_vsa_active        ON vendor_serving_areas (is_active) WHERE is_active = true;

-- ── Row Level Security ────────────────────────────────────────────────────────

ALTER TABLE vendor_serving_areas             ENABLE ROW LEVEL SECURITY;
ALTER TABLE vendor_serving_area_assignments  ENABLE ROW LEVEL SECURITY;

-- vendor_serving_areas: public read (vendor/customer apps), auth write (admin)
CREATE POLICY "vsa_anon_read"  ON vendor_serving_areas FOR SELECT TO anon         USING (true);
CREATE POLICY "vsa_auth_read"  ON vendor_serving_areas FOR SELECT TO authenticated USING (true);
CREATE POLICY "vsa_auth_write" ON vendor_serving_areas FOR ALL    TO authenticated USING (true) WITH CHECK (true);

-- vendor_serving_area_assignments: auth read/write (vendors + admin)
CREATE POLICY "vsaa_anon_read"  ON vendor_serving_area_assignments FOR SELECT TO anon         USING (true);
CREATE POLICY "vsaa_auth_all"   ON vendor_serving_area_assignments FOR ALL    TO authenticated USING (true) WITH CHECK (true);
