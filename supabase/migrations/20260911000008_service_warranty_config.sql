-- ── Per-Service Warranty Configuration ─────────────────────────────────────
--
-- Adds warranty_enabled / warranty_days to catalog_nodes so each bookable
-- service can independently opt into warranty coverage and set its own period.
--
-- Trigger fn_auto_generate_service_warranty is updated to:
--   1. Look up the booking's primary catalog_node via booking_items.service_id
--   2. Only create a warranty when is_bookable = true AND warranty_enabled = true
--   3. Use the service's warranty_days (snapshotted into service_warranties.warranty_days)
--   4. Non-bookable services and services with warranty_enabled = false → no warranty
--
-- Existing service_warranty rows are untouched (expires_at already snapshotted).
-- The global 'default_warranty_days' setting is no longer consulted by this trigger;
-- it is kept in the settings table for backwards-compat but is now unused.
-- ────────────────────────────────────────────────────────────────────────────

-- 1. New columns on catalog_nodes
ALTER TABLE public.catalog_nodes
  ADD COLUMN IF NOT EXISTS warranty_enabled BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS warranty_days     INT;

-- Ensure warranty_days is positive when warranty is enabled
ALTER TABLE public.catalog_nodes
  ADD CONSTRAINT chk_catalog_nodes_warranty_config
    CHECK (
      NOT warranty_enabled
      OR (warranty_days IS NOT NULL AND warranty_days > 0)
    );

-- 2. Refresh catalog_nodes_view to expose the two new columns.
--    Column order follows 20260831000001 exactly; new columns appended at end.

DROP VIEW IF EXISTS catalog_nodes_view;

CREATE VIEW catalog_nodes_view AS
SELECT
  n.id,
  n.name,
  n.slug,
  n.description,
  n.image_url,
  n.mobile_image_url,
  n.icon_key,
  n.sort_order,
  n.is_active,
  n.is_bookable,
  n.base_price,
  n.estimated_duration,
  n.minimum_order_amount,
  n.loyalty_earn_enabled,
  n.loyalty_earn_rule,
  n.loyalty_fixed_points,
  n.loyalty_earn_per_100,
  n.rating,
  n.review_count,
  n.created_at,
  n.updated_at,
  n.included_items,
  n.excluded_items,
  n.before_after_pairs,
  n.content_blocks,
  n.discount_type,
  n.discount_value,
  (
    SELECT COUNT(*)::INTEGER
    FROM   catalog_node_relationships r
    JOIN   catalog_nodes c ON c.id = r.child_id
    WHERE  r.parent_id = n.id
      AND  c.is_active = true
      AND  COALESCE(r.availability_status, 'active') <> 'hidden'
      AND  COALESCE(c.availability_status, 'active') <> 'hidden'
  ) AS children_count,

  (
    SELECT p.name
    FROM   catalog_node_relationships r
    JOIN   catalog_nodes p ON p.id = r.parent_id
    WHERE  r.child_id = n.id
    ORDER  BY r.sort_order ASC, r.created_at ASC
    LIMIT  1
  ) AS parent_name,

  (
    SELECT p.slug
    FROM   catalog_node_relationships r
    JOIN   catalog_nodes p ON p.id = r.parent_id
    WHERE  r.child_id = n.id
    ORDER  BY r.sort_order ASC, r.created_at ASC
    LIMIT  1
  ) AS parent_slug,

  COALESCE(
    (
      SELECT array_agg(r.parent_id::TEXT ORDER BY r.sort_order ASC, r.created_at ASC)
      FROM   catalog_node_relationships r
      WHERE  r.child_id = n.id
    ),
    ARRAY[]::TEXT[]
  ) AS parent_ids,

  NOT EXISTS (
    SELECT 1 FROM catalog_node_relationships r WHERE r.child_id = n.id
  ) AS is_root_node,

  n.availability_status,
  n.unavailability_message,
  n.warranty_enabled,
  n.warranty_days
FROM catalog_nodes n;


-- 3. Refresh get_catalog_node_children with the two new columns.

DROP FUNCTION IF EXISTS get_catalog_node_children(UUID);

CREATE FUNCTION get_catalog_node_children(p_parent_id UUID)
RETURNS TABLE (
  id                         UUID,
  name                       TEXT,
  slug                       TEXT,
  description                TEXT,
  image_url                  TEXT,
  mobile_image_url           TEXT,
  icon_key                   TEXT,
  sort_order                 INTEGER,
  is_active                  BOOLEAN,
  is_bookable                BOOLEAN,
  base_price                 NUMERIC,
  estimated_duration         INTEGER,
  minimum_order_amount       NUMERIC,
  loyalty_earn_enabled       BOOLEAN,
  loyalty_earn_rule          TEXT,
  loyalty_fixed_points       INTEGER,
  loyalty_earn_per_100       INTEGER,
  rating                     NUMERIC,
  review_count               INTEGER,
  created_at                 TIMESTAMPTZ,
  updated_at                 TIMESTAMPTZ,
  included_items             JSONB,
  excluded_items             JSONB,
  before_after_pairs         JSONB,
  content_blocks             JSONB,
  discount_type              TEXT,
  discount_value             NUMERIC,
  children_count             INTEGER,
  parent_name                TEXT,
  parent_slug                TEXT,
  parent_ids                 TEXT[],
  is_root_node               BOOLEAN,
  availability_status        TEXT,
  unavailability_message     TEXT,
  rel_availability_status    TEXT,
  rel_unavailability_message TEXT,
  warranty_enabled           BOOLEAN,
  warranty_days              INTEGER
)
LANGUAGE SQL
STABLE
AS $$
  SELECT
    v.id,
    v.name,
    v.slug,
    v.description,
    v.image_url,
    v.mobile_image_url,
    v.icon_key,
    v.sort_order,
    v.is_active,
    v.is_bookable,
    v.base_price,
    v.estimated_duration,
    v.minimum_order_amount,
    v.loyalty_earn_enabled,
    v.loyalty_earn_rule,
    v.loyalty_fixed_points,
    v.loyalty_earn_per_100,
    v.rating,
    v.review_count,
    v.created_at,
    v.updated_at,
    v.included_items,
    v.excluded_items,
    v.before_after_pairs,
    v.content_blocks,
    v.discount_type,
    v.discount_value,
    v.children_count,
    v.parent_name,
    v.parent_slug,
    v.parent_ids,
    v.is_root_node,
    v.availability_status,
    v.unavailability_message,
    r.availability_status    AS rel_availability_status,
    r.unavailability_message AS rel_unavailability_message,
    v.warranty_enabled,
    v.warranty_days
  FROM   catalog_node_relationships r
  JOIN   catalog_nodes_view v ON v.id = r.child_id
  WHERE  r.parent_id = p_parent_id
    AND  v.is_active = true
    AND  COALESCE(r.availability_status, 'active') <> 'hidden'
    AND  COALESCE(v.availability_status, 'active') <> 'hidden'
  ORDER  BY r.sort_order ASC, v.name ASC;
$$;


-- 4. Update warranty generation trigger to use per-service config.
--    Old behaviour: read 'default_warranty_days' from settings, apply to ALL bookings.
--    New behaviour: resolve catalog_node from booking_items; only generate warranty
--                   when the node is bookable AND warranty_enabled = true.

CREATE OR REPLACE FUNCTION public.fn_auto_generate_service_warranty()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_service_id   UUID;
  v_warranty_days INT;
  v_expires_at   TIMESTAMPTZ;
BEGIN
  IF NEW.status = 'completed' AND (OLD.status IS NULL OR OLD.status != 'completed') THEN
    IF NOT EXISTS (SELECT 1 FROM public.service_warranties WHERE booking_id = NEW.id) THEN

      -- Resolve the primary catalog_node for this booking
      SELECT bi.service_id
      INTO   v_service_id
      FROM   public.booking_items bi
      WHERE  bi.booking_id = NEW.id
        AND  bi.service_id IS NOT NULL
      LIMIT  1;

      IF v_service_id IS NOT NULL THEN
        -- Only generate warranty when the service explicitly has warranty enabled
        SELECT cn.warranty_days
        INTO   v_warranty_days
        FROM   public.catalog_nodes cn
        WHERE  cn.id             = v_service_id
          AND  cn.is_bookable    = true
          AND  cn.warranty_enabled = true
          AND  cn.warranty_days  IS NOT NULL
          AND  cn.warranty_days  > 0;

        IF v_warranty_days IS NOT NULL THEN
          v_expires_at := now() + (v_warranty_days || ' days')::INTERVAL;

          INSERT INTO public.service_warranties (
            booking_id, customer_id, vendor_id, warranty_days,
            issued_at, expires_at, status, created_at, updated_at
          ) VALUES (
            NEW.id, NEW.customer_id, NEW.vendor_id, v_warranty_days,
            now(), v_expires_at, 'Active', now(), now()
          );
        END IF;
      END IF;

    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- Re-create trigger (idempotent; same name as existing trigger)
DROP TRIGGER IF EXISTS trg_auto_generate_service_warranty ON public.bookings;
CREATE TRIGGER trg_auto_generate_service_warranty
  AFTER INSERT OR UPDATE OF status ON public.bookings
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_auto_generate_service_warranty();

NOTIFY pgrst, 'reload schema';
