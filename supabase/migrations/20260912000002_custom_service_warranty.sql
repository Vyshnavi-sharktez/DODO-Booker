-- ── Vendor Custom Service Warranty Configuration ──────────────────────────────
--
-- 1. vendor_service_requests: add warranty_enabled, warranty_days, warranty_covers,
--    warranty_exclusions so each approved custom service can independently opt into
--    warranty coverage and configure its own terms.
--
-- 2. service_warranties: add warranty_covers, warranty_exclusions so the exact terms
--    shown to the customer are snapshotted at issuance time (immutable even if the
--    vendor later edits the custom service or admin edits the catalog node).
--
-- 3. fn_auto_generate_service_warranty: updated to:
--    a) Snapshot warranty_covers / warranty_exclusions into service_warranties for
--       the existing catalog_nodes path.
--    b) Add a new custom-service path that reads from vendor_service_requests when
--       the booking item has a custom_service_id instead of a service_id.
--
-- 4. search_vendor_custom_services RPC: extended with warranty fields so the customer
--    detail sheet can render the warranty badge without a second query.
-- ─────────────────────────────────────────────────────────────────────────────

-- 1. Warranty columns on vendor_service_requests
ALTER TABLE public.vendor_service_requests
  ADD COLUMN IF NOT EXISTS warranty_enabled    BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS warranty_days       INT,
  ADD COLUMN IF NOT EXISTS warranty_covers     TEXT,
  ADD COLUMN IF NOT EXISTS warranty_exclusions TEXT;

ALTER TABLE public.vendor_service_requests
  ADD CONSTRAINT chk_vsr_warranty_config
    CHECK (
      NOT warranty_enabled
      OR (warranty_days IS NOT NULL AND warranty_days > 0)
    );

-- 2. Snapshot columns on service_warranties
ALTER TABLE public.service_warranties
  ADD COLUMN IF NOT EXISTS warranty_covers     TEXT,
  ADD COLUMN IF NOT EXISTS warranty_exclusions TEXT;

-- 3. Update warranty generation trigger
--    Old: catalog_nodes path only, no terms snapshot.
--    New: catalog_nodes path (with terms snapshot) + vendor_service_requests path.

CREATE OR REPLACE FUNCTION public.fn_auto_generate_service_warranty()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_service_id      UUID;
  v_custom_svc_id   UUID;
  v_warranty_days   INT;
  v_warranty_covers TEXT;
  v_warranty_excl   TEXT;
  v_expires_at      TIMESTAMPTZ;
BEGIN
  IF NEW.status = 'completed' AND (OLD.status IS NULL OR OLD.status != 'completed') THEN
    IF NOT EXISTS (SELECT 1 FROM public.service_warranties WHERE booking_id = NEW.id) THEN

      -- Path 1: catalog node (service_id IS NOT NULL)
      SELECT bi.service_id
      INTO   v_service_id
      FROM   public.booking_items bi
      WHERE  bi.booking_id = NEW.id
        AND  bi.service_id IS NOT NULL
      LIMIT  1;

      IF v_service_id IS NOT NULL THEN
        SELECT cn.warranty_days, cn.warranty_covers, cn.warranty_exclusions
        INTO   v_warranty_days, v_warranty_covers, v_warranty_excl
        FROM   public.catalog_nodes cn
        WHERE  cn.id              = v_service_id
          AND  cn.is_bookable     = true
          AND  cn.warranty_enabled = true
          AND  cn.warranty_days   IS NOT NULL
          AND  cn.warranty_days   > 0;
      END IF;

      -- Path 2: vendor custom service (only when catalog path yielded no warranty)
      IF v_warranty_days IS NULL THEN
        SELECT bi.custom_service_id
        INTO   v_custom_svc_id
        FROM   public.booking_items bi
        WHERE  bi.booking_id = NEW.id
          AND  bi.custom_service_id IS NOT NULL
        LIMIT  1;

        IF v_custom_svc_id IS NOT NULL THEN
          SELECT vsr.warranty_days, vsr.warranty_covers, vsr.warranty_exclusions
          INTO   v_warranty_days, v_warranty_covers, v_warranty_excl
          FROM   public.vendor_service_requests vsr
          WHERE  vsr.id               = v_custom_svc_id
            AND  vsr.warranty_enabled  = true
            AND  vsr.warranty_days    IS NOT NULL
            AND  vsr.warranty_days    > 0;
        END IF;
      END IF;

      IF v_warranty_days IS NOT NULL THEN
        v_expires_at := now() + (v_warranty_days || ' days')::INTERVAL;

        INSERT INTO public.service_warranties (
          booking_id, customer_id, vendor_id, warranty_days,
          warranty_covers, warranty_exclusions,
          issued_at, expires_at, status, created_at, updated_at
        ) VALUES (
          NEW.id, NEW.customer_id, NEW.vendor_id, v_warranty_days,
          v_warranty_covers, v_warranty_excl,
          now(), v_expires_at, 'Active', now(), now()
        );
      END IF;

    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- Trigger is already defined; re-create to pick up function changes.
DROP TRIGGER IF EXISTS trg_auto_generate_service_warranty ON public.bookings;
CREATE TRIGGER trg_auto_generate_service_warranty
  AFTER INSERT OR UPDATE OF status ON public.bookings
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_auto_generate_service_warranty();

-- 4. Rebuild search_vendor_custom_services RPC to include warranty fields.
--    Must DROP + CREATE because RETURNS TABLE column list cannot change with
--    CREATE OR REPLACE when column count differs.

DROP FUNCTION IF EXISTS search_vendor_custom_services(TEXT);

CREATE FUNCTION search_vendor_custom_services(p_query TEXT)
RETURNS TABLE (
  id                  UUID,
  service_name        TEXT,
  description         TEXT,
  active_price        NUMERIC,
  image_url           TEXT,
  vendor_id           UUID,
  vendor_name         TEXT,
  rating              NUMERIC,
  review_count        INTEGER,
  included_items      JSONB,
  excluded_items      JSONB,
  before_after_pairs  JSONB,
  warranty_enabled    BOOLEAN,
  warranty_days       INTEGER,
  warranty_covers     TEXT,
  warranty_exclusions TEXT
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    vsr.id,
    vsr.service_name,
    vsr.description,
    vsr.active_price,
    vsr.image_url,
    vsr.vendor_id,
    v.business_name      AS vendor_name,
    vsr.rating,
    vsr.review_count,
    vsr.included_items,
    vsr.excluded_items,
    vsr.before_after_pairs,
    vsr.warranty_enabled,
    vsr.warranty_days,
    vsr.warranty_covers,
    vsr.warranty_exclusions
  FROM vendor_service_requests vsr
  JOIN vendors v ON v.id = vsr.vendor_id
  WHERE vsr.request_type = 'new_service'
    AND vsr.status       = 'completed'
    AND v.is_active      = true
    AND (
      vsr.service_name ILIKE '%' || p_query || '%'
      OR vsr.description ILIKE '%' || p_query || '%'
    )
  ORDER BY vsr.service_name
  LIMIT 50;
$$;

GRANT EXECUTE ON FUNCTION search_vendor_custom_services(TEXT) TO anon, authenticated;

NOTIFY pgrst, 'reload schema';
