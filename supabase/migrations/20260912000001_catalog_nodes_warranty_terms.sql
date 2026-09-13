-- ── Per-Service Warranty Terms ───────────────────────────────────────────────
--
-- Adds warranty_covers / warranty_exclusions TEXT columns to catalog_nodes so
-- each bookable service can store its own warranty terms independently.
--
-- Existing warranty-enabled services are pre-populated with the generic default
-- text that was previously hardcoded in the customer app, so existing behavior
-- is preserved without any visible change until the admin customises the terms.
-- ────────────────────────────────────────────────────────────────────────────

-- 1. New columns
ALTER TABLE public.catalog_nodes
  ADD COLUMN IF NOT EXISTS warranty_covers     TEXT,
  ADD COLUMN IF NOT EXISTS warranty_exclusions TEXT;

-- 2. Back-fill existing warranty-enabled nodes with the legacy default text
UPDATE public.catalog_nodes
SET
  warranty_covers = 'Workmanship and labor quality for the service performed.
Spare parts and replacement components supplied during the service.
Operational defects directly arising from the completed job within the warranty period.',
  warranty_exclusions = 'Physical, liquid, or accidental damage occurring post-service completion.
Misuse, unauthorized third-party tampering, or electrical voltage surges.
Normal wear and tear or pre-existing defects not included in the original job scope.'
WHERE warranty_enabled = true
  AND warranty_covers IS NULL;

-- 3. Refresh catalog_nodes_view to expose the two new columns.
--    Column order follows 20260911000008 exactly; new columns appended at end.

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
  n.warranty_days,
  n.warranty_covers,
  n.warranty_exclusions
FROM catalog_nodes n;


-- 4. Refresh get_catalog_node_children with the two new columns.

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
  warranty_days              INTEGER,
  warranty_covers            TEXT,
  warranty_exclusions        TEXT
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
    v.warranty_days,
    v.warranty_covers,
    v.warranty_exclusions
  FROM   catalog_node_relationships r
  JOIN   catalog_nodes_view v ON v.id = r.child_id
  WHERE  r.parent_id = p_parent_id
    AND  v.is_active = true
    AND  COALESCE(r.availability_status, 'active') <> 'hidden'
    AND  COALESCE(v.availability_status, 'active') <> 'hidden'
  ORDER  BY r.sort_order ASC, v.name ASC;
$$;


NOTIFY pgrst, 'reload schema';
