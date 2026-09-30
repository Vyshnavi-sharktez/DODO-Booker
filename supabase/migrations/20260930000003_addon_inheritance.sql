-- ── Addon Inheritance for Catalog Nodes ──────────────────────────────────────
--
-- Replaces the simple addons.service_id 1:1 assignment with a junction table
-- that supports inheritance through the catalog hierarchy.
--
-- Inheritance rules (evaluated per service node):
--   1. Node has rows in catalog_node_addons          → use those addons
--   2. Node has no rows but addon_override = TRUE    → no addons (explicit block)
--   3. Node has no rows and addon_override = FALSE   → walk up parent chain
--      repeating rule 1/2 until a source is found
--
-- Existing addons.service_id assignments are migrated into catalog_node_addons
-- so existing behaviour is preserved immediately after the migration runs.

-- ── 1. Junction table ─────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS catalog_node_addons (
  node_id    UUID NOT NULL REFERENCES catalog_nodes(id) ON DELETE CASCADE,
  addon_id   UUID NOT NULL REFERENCES addons(id)        ON DELETE CASCADE,
  sort_order INT  NOT NULL DEFAULT 0,
  PRIMARY KEY (node_id, addon_id)
);

CREATE INDEX IF NOT EXISTS idx_catalog_node_addons_node_id
  ON catalog_node_addons (node_id);

-- ── 2. Override flag on catalog_nodes ─────────────────────────────────────────

ALTER TABLE catalog_nodes
  ADD COLUMN IF NOT EXISTS addon_override BOOLEAN NOT NULL DEFAULT FALSE;

-- ── 3. Migrate existing service_id assignments ────────────────────────────────
-- Each addon whose service_id points to a valid catalog node becomes a row
-- in catalog_node_addons.  ON CONFLICT DO NOTHING is idempotent.

INSERT INTO catalog_node_addons (node_id, addon_id, sort_order)
SELECT  a.service_id, a.id, 0
FROM    addons a
WHERE   a.service_id IS NOT NULL
  AND   EXISTS (SELECT 1 FROM catalog_nodes cn WHERE cn.id = a.service_id)
ON CONFLICT DO NOTHING;

-- ── 4. RLS ────────────────────────────────────────────────────────────────────
-- App uses anon key (no Supabase Auth session) — same pattern as cart_items
-- (migration 20260616000001).

ALTER TABLE catalog_node_addons ENABLE ROW LEVEL SECURITY;

CREATE POLICY "anon_select_catalog_node_addons"
  ON catalog_node_addons FOR SELECT TO anon USING (true);

CREATE POLICY "anon_insert_catalog_node_addons"
  ON catalog_node_addons FOR INSERT TO anon WITH CHECK (true);

CREATE POLICY "anon_update_catalog_node_addons"
  ON catalog_node_addons FOR UPDATE TO anon USING (true) WITH CHECK (true);

CREATE POLICY "anon_delete_catalog_node_addons"
  ON catalog_node_addons FOR DELETE TO anon USING (true);

CREATE POLICY "service_role_all_catalog_node_addons"
  ON catalog_node_addons FOR ALL TO service_role USING (true) WITH CHECK (true);

-- ── 5. Batch addon resolution function ───────────────────────────────────────
-- Returns resolved addons for an array of service node IDs.
-- source_node_id identifies which service the row belongs to so callers can
-- group by service.  Inactive addons are excluded.

CREATE OR REPLACE FUNCTION resolve_node_addons_batch(p_node_ids UUID[])
RETURNS TABLE (
  source_node_id UUID,
  id             UUID,
  name           TEXT,
  description    TEXT,
  price          NUMERIC,
  is_active      BOOLEAN,
  discount_type  TEXT,
  discount_value NUMERIC,
  sort_order     INT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
AS $$
DECLARE
  nid           UUID;
  current_id    UUID;
  found_id      UUID;
  has_own       BOOLEAN;
  has_override  BOOLEAN;
BEGIN
  FOREACH nid IN ARRAY p_node_ids LOOP
    current_id := nid;
    found_id   := NULL;

    -- Walk the hierarchy until a source node is identified
    LOOP
      SELECT EXISTS(
        SELECT 1 FROM catalog_node_addons cna WHERE cna.node_id = current_id
      ) INTO has_own;

      SELECT COALESCE(cn.addon_override, FALSE)
      INTO   has_override
      FROM   catalog_nodes cn
      WHERE  cn.id = current_id;

      IF has_own OR has_override THEN
        found_id := current_id;
        EXIT;
      END IF;

      -- Walk up to the first parent in the catalog hierarchy
      SELECT cnr.parent_id INTO current_id
      FROM   catalog_node_relationships cnr
      WHERE  cnr.child_id = current_id
      LIMIT  1;

      EXIT WHEN current_id IS NULL;
    END LOOP;

    -- Emit addon rows for this service
    IF found_id IS NOT NULL THEN
      RETURN QUERY
        SELECT
          nid                AS source_node_id,
          a.id,
          a.name,
          a.description,
          a.price,
          a.is_active,
          a.discount_type,
          a.discount_value,
          cna.sort_order
        FROM   catalog_node_addons cna
        JOIN   addons a ON a.id = cna.addon_id
        WHERE  cna.node_id = found_id
          AND  a.is_active = TRUE
        ORDER BY cna.sort_order ASC, a.name ASC;
    END IF;
    -- found_id = NULL → no addons for this service (zero rows emitted for nid)
  END LOOP;
END;
$$;

GRANT EXECUTE ON FUNCTION resolve_node_addons_batch(UUID[])
  TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';
