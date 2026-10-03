-- Migration: Automatic sort-order management
-- Adds RPCs for move-up/down, next-position, and post-delete normalization
-- for catalog nodes, service FAQs, subscription plans, and attribute options.

-- ── 1. Catalog nodes: next sort_order within scope ────────────────────────────
-- p_parent_id IS NULL  → among root nodes (no parent relationship)
-- p_parent_id non-NULL → among children of that parent (by catalog_nodes.sort_order)

CREATE OR REPLACE FUNCTION get_next_catalog_sort_order(
  p_parent_id UUID DEFAULT NULL
)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_parent_id IS NULL THEN
    RETURN COALESCE(
      (SELECT MAX(cn.sort_order)
         FROM catalog_nodes cn
        WHERE NOT EXISTS (
              SELECT 1 FROM catalog_node_relationships r WHERE r.child_id = cn.id
            )),
      -1
    ) + 1;
  ELSE
    RETURN COALESCE(
      (SELECT MAX(cn.sort_order)
         FROM catalog_nodes cn
         JOIN catalog_node_relationships r ON r.child_id = cn.id
        WHERE r.parent_id = p_parent_id),
      -1
    ) + 1;
  END IF;
END;
$$;

-- ── 2. Catalog nodes: swap sort_order with adjacent sibling ───────────────────
-- Swaps catalog_nodes.sort_order (the single column the admin UI sorts by).
-- p_parent_id IS NULL  → among root nodes
-- p_parent_id non-NULL → among children of that parent
-- p_direction          → 'up' (lower index) or 'down' (higher index)

CREATE OR REPLACE FUNCTION move_catalog_node(
  p_node_id   UUID,
  p_parent_id UUID,
  p_direction TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cur  INT;
  v_nid  UUID;
  v_nord INT;
BEGIN
  SELECT sort_order INTO v_cur FROM catalog_nodes WHERE id = p_node_id;
  IF NOT FOUND THEN RETURN; END IF;

  IF p_parent_id IS NULL THEN
    IF p_direction = 'up' THEN
      SELECT cn.id, cn.sort_order INTO v_nid, v_nord
        FROM catalog_nodes cn
       WHERE cn.sort_order < v_cur
         AND NOT EXISTS (SELECT 1 FROM catalog_node_relationships r WHERE r.child_id = cn.id)
       ORDER BY cn.sort_order DESC LIMIT 1;
    ELSE
      SELECT cn.id, cn.sort_order INTO v_nid, v_nord
        FROM catalog_nodes cn
       WHERE cn.sort_order > v_cur
         AND NOT EXISTS (SELECT 1 FROM catalog_node_relationships r WHERE r.child_id = cn.id)
       ORDER BY cn.sort_order ASC LIMIT 1;
    END IF;
  ELSE
    IF p_direction = 'up' THEN
      SELECT cn.id, cn.sort_order INTO v_nid, v_nord
        FROM catalog_nodes cn
        JOIN catalog_node_relationships r ON r.child_id = cn.id
       WHERE r.parent_id = p_parent_id
         AND cn.id <> p_node_id
         AND cn.sort_order < v_cur
       ORDER BY cn.sort_order DESC LIMIT 1;
    ELSE
      SELECT cn.id, cn.sort_order INTO v_nid, v_nord
        FROM catalog_nodes cn
        JOIN catalog_node_relationships r ON r.child_id = cn.id
       WHERE r.parent_id = p_parent_id
         AND cn.id <> p_node_id
         AND cn.sort_order > v_cur
       ORDER BY cn.sort_order ASC LIMIT 1;
    END IF;
  END IF;

  IF v_nid IS NULL THEN RETURN; END IF;

  -- Use -1 as a transient value to avoid collisions during the two-step swap.
  UPDATE catalog_nodes SET sort_order = -1      WHERE id = p_node_id;
  UPDATE catalog_nodes SET sort_order = v_cur   WHERE id = v_nid;
  UPDATE catalog_nodes SET sort_order = v_nord  WHERE id = p_node_id;
END;
$$;

-- ── 3. Catalog nodes: close gaps after delete ─────────────────────────────────
-- Renumbers root nodes (p_parent_id IS NULL) or a specific parent's children
-- to contiguous 0-based integers ordered by current sort_order.
-- NOTE: since sort_order is stored on catalog_nodes (not per-relationship),
-- normalising a parent's children writes to the same global column; call only
-- for root-level normalisation or when a node has a single parent.

CREATE OR REPLACE FUNCTION normalize_catalog_sort_order(
  p_parent_id UUID DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_parent_id IS NULL THEN
    WITH ordered AS (
      SELECT cn.id,
             (ROW_NUMBER() OVER (ORDER BY cn.sort_order ASC, cn.name ASC) - 1) AS new_order
        FROM catalog_nodes cn
       WHERE NOT EXISTS (
             SELECT 1 FROM catalog_node_relationships r WHERE r.child_id = cn.id
           )
    )
    UPDATE catalog_nodes
       SET sort_order = ordered.new_order
      FROM ordered
     WHERE catalog_nodes.id = ordered.id;
  ELSE
    WITH ordered AS (
      SELECT cn.id,
             (ROW_NUMBER() OVER (ORDER BY cn.sort_order ASC, cn.name ASC) - 1) AS new_order
        FROM catalog_nodes cn
        JOIN catalog_node_relationships rel ON rel.child_id = cn.id
       WHERE rel.parent_id = p_parent_id
    )
    UPDATE catalog_nodes
       SET sort_order = ordered.new_order
      FROM ordered
     WHERE catalog_nodes.id = ordered.id;
  END IF;
END;
$$;

-- ── 4. Subscription plans: next sort_order ────────────────────────────────────

CREATE OR REPLACE FUNCTION get_next_subscription_plan_sort_order()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN COALESCE((SELECT MAX(sort_order) FROM subscription_plans), -1) + 1;
END;
$$;

-- ── 5. Subscription plans: move up / down ────────────────────────────────────

CREATE OR REPLACE FUNCTION move_subscription_plan(
  p_plan_id   UUID,
  p_direction TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cur  INT;
  v_nid  UUID;
  v_nord INT;
BEGIN
  SELECT sort_order INTO v_cur FROM subscription_plans WHERE id = p_plan_id;
  IF NOT FOUND THEN RETURN; END IF;

  IF p_direction = 'up' THEN
    SELECT id, sort_order INTO v_nid, v_nord
      FROM subscription_plans
     WHERE sort_order < v_cur
     ORDER BY sort_order DESC LIMIT 1;
  ELSE
    SELECT id, sort_order INTO v_nid, v_nord
      FROM subscription_plans
     WHERE sort_order > v_cur
     ORDER BY sort_order ASC LIMIT 1;
  END IF;

  IF v_nid IS NULL THEN RETURN; END IF;

  UPDATE subscription_plans SET sort_order = -1     WHERE id = p_plan_id;
  UPDATE subscription_plans SET sort_order = v_cur  WHERE id = v_nid;
  UPDATE subscription_plans SET sort_order = v_nord WHERE id = p_plan_id;
END;
$$;

-- ── 6. Subscription plans: close gaps after delete ───────────────────────────

CREATE OR REPLACE FUNCTION normalize_subscription_plan_sort_orders()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  WITH ordered AS (
    SELECT id,
           (ROW_NUMBER() OVER (ORDER BY sort_order ASC, created_at ASC) - 1) AS new_order
      FROM subscription_plans
  )
  UPDATE subscription_plans
     SET sort_order = ordered.new_order
    FROM ordered
   WHERE subscription_plans.id = ordered.id;
END;
$$;

-- ── 7. Service FAQs: move up / down ──────────────────────────────────────────
-- Scoped by service_id or custom_service_id (whichever is non-null on the row).

CREATE OR REPLACE FUNCTION move_service_faq(
  p_faq_id    UUID,
  p_direction TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sid  UUID;
  v_csid UUID;
  v_cur  INT;
  v_nid  UUID;
  v_nord INT;
BEGIN
  SELECT service_id, custom_service_id, sort_order
    INTO v_sid, v_csid, v_cur
    FROM service_faqs WHERE id = p_faq_id;
  IF NOT FOUND THEN RETURN; END IF;

  IF p_direction = 'up' THEN
    SELECT id, sort_order INTO v_nid, v_nord
      FROM service_faqs
     WHERE sort_order < v_cur
       AND (
             (v_sid  IS NOT NULL AND service_id        = v_sid)
          OR (v_csid IS NOT NULL AND custom_service_id = v_csid)
           )
     ORDER BY sort_order DESC LIMIT 1;
  ELSE
    SELECT id, sort_order INTO v_nid, v_nord
      FROM service_faqs
     WHERE sort_order > v_cur
       AND (
             (v_sid  IS NOT NULL AND service_id        = v_sid)
          OR (v_csid IS NOT NULL AND custom_service_id = v_csid)
           )
     ORDER BY sort_order ASC LIMIT 1;
  END IF;

  IF v_nid IS NULL THEN RETURN; END IF;

  UPDATE service_faqs SET sort_order = -1     WHERE id = p_faq_id;
  UPDATE service_faqs SET sort_order = v_cur  WHERE id = v_nid;
  UPDATE service_faqs SET sort_order = v_nord WHERE id = p_faq_id;
END;
$$;

-- ── 8. Service FAQs: close gaps after delete ─────────────────────────────────

CREATE OR REPLACE FUNCTION normalize_service_faq_sort_orders(
  p_service_id        UUID DEFAULT NULL,
  p_custom_service_id UUID DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_service_id IS NOT NULL THEN
    WITH ordered AS (
      SELECT id,
             (ROW_NUMBER() OVER (ORDER BY sort_order ASC) - 1) AS new_order
        FROM service_faqs
       WHERE service_id = p_service_id
    )
    UPDATE service_faqs
       SET sort_order = ordered.new_order
      FROM ordered
     WHERE service_faqs.id = ordered.id
       AND service_faqs.service_id = p_service_id;

  ELSIF p_custom_service_id IS NOT NULL THEN
    WITH ordered AS (
      SELECT id,
             (ROW_NUMBER() OVER (ORDER BY sort_order ASC) - 1) AS new_order
        FROM service_faqs
       WHERE custom_service_id = p_custom_service_id
    )
    UPDATE service_faqs
       SET sort_order = ordered.new_order
      FROM ordered
     WHERE service_faqs.id = ordered.id
       AND service_faqs.custom_service_id = p_custom_service_id;
  END IF;
END;
$$;

-- ── 9. Service attribute options: close gaps after delete ─────────────────────

CREATE OR REPLACE FUNCTION normalize_attribute_option_sort_orders(
  p_attribute_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  WITH ordered AS (
    SELECT id,
           (ROW_NUMBER() OVER (ORDER BY sort_order ASC) - 1) AS new_order
      FROM service_attribute_options
     WHERE attribute_id = p_attribute_id
  )
  UPDATE service_attribute_options
     SET sort_order = ordered.new_order
    FROM ordered
   WHERE service_attribute_options.id = ordered.id
     AND service_attribute_options.attribute_id = p_attribute_id;
END;
$$;

-- ── 10. Backfill: normalize existing data ────────────────────────────────────
-- Ensure all existing sort_order values are contiguous within their scopes.
-- Safe to run multiple times (idempotent).

DO $$
DECLARE
  v_parent UUID;
BEGIN
  -- Normalize root catalog nodes
  WITH ordered AS (
    SELECT cn.id,
           (ROW_NUMBER() OVER (ORDER BY cn.sort_order ASC, cn.name ASC) - 1) AS new_order
      FROM catalog_nodes cn
     WHERE NOT EXISTS (
             SELECT 1 FROM catalog_node_relationships r WHERE r.child_id = cn.id
           )
  )
  UPDATE catalog_nodes
     SET sort_order = ordered.new_order
    FROM ordered
   WHERE catalog_nodes.id = ordered.id;

  -- Normalize subscription plans
  WITH ordered AS (
    SELECT id,
           (ROW_NUMBER() OVER (ORDER BY sort_order ASC, created_at ASC) - 1) AS new_order
      FROM subscription_plans
  )
  UPDATE subscription_plans
     SET sort_order = ordered.new_order
    FROM ordered
   WHERE subscription_plans.id = ordered.id;

  -- Normalize service FAQs per service_id
  FOR v_parent IN (SELECT DISTINCT service_id FROM service_faqs WHERE service_id IS NOT NULL)
  LOOP
    WITH ordered AS (
      SELECT id,
             (ROW_NUMBER() OVER (ORDER BY sort_order ASC) - 1) AS new_order
        FROM service_faqs
       WHERE service_id = v_parent
    )
    UPDATE service_faqs
       SET sort_order = ordered.new_order
      FROM ordered
     WHERE service_faqs.id = ordered.id
       AND service_faqs.service_id = v_parent;
  END LOOP;

  -- Normalize service FAQs per custom_service_id
  FOR v_parent IN (SELECT DISTINCT custom_service_id FROM service_faqs WHERE custom_service_id IS NOT NULL)
  LOOP
    WITH ordered AS (
      SELECT id,
             (ROW_NUMBER() OVER (ORDER BY sort_order ASC) - 1) AS new_order
        FROM service_faqs
       WHERE custom_service_id = v_parent
    )
    UPDATE service_faqs
       SET sort_order = ordered.new_order
      FROM ordered
     WHERE service_faqs.id = ordered.id
       AND service_faqs.custom_service_id = v_parent;
  END LOOP;

  -- Normalize attribute options per attribute_id
  FOR v_parent IN (SELECT DISTINCT attribute_id FROM service_attribute_options)
  LOOP
    WITH ordered AS (
      SELECT id,
             (ROW_NUMBER() OVER (ORDER BY sort_order ASC) - 1) AS new_order
        FROM service_attribute_options
       WHERE attribute_id = v_parent
    )
    UPDATE service_attribute_options
       SET sort_order = ordered.new_order
      FROM ordered
     WHERE service_attribute_options.id = ordered.id
       AND service_attribute_options.attribute_id = v_parent;
  END LOOP;
END;
$$;
