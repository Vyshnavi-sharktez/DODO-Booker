-- cart_items: add parent_node_id to track which catalog occurrence was added.
--
-- WHY: The same catalog_nodes row (same UUID) can appear under multiple parent
-- categories via catalog_node_relationships (shared-node architecture). Without
-- parent_node_id, cart entries from different paths for the same shared node
-- collide: adding from Home Cleaning marks AC Services as "in cart" and vice
-- versa. parent_node_id scopes each cart row to the catalog occurrence.
--
-- UNIQUENESS: The old constraint was (customer_id, service_id). The new
-- constraint is (customer_id, service_id, parent_node_id) with NULLS NOT
-- DISTINCT so that NULL parent_node_id is treated as a distinct, comparable
-- value (two NULL rows for the same customer+service still conflict).
--
-- EXISTING DATA: All existing rows get parent_node_id = NULL, which is a valid
-- sentinel meaning "opened without a known parent context" (e.g. search,
-- notification, deep-link). They are preserved unchanged.

-- ── 1. Add column ────────────────────────────────────────────────────────────

ALTER TABLE public.cart_items
  ADD COLUMN IF NOT EXISTS parent_node_id UUID
    REFERENCES public.catalog_nodes(id) ON DELETE SET NULL;

-- ── 2. Drop existing unique constraint on (customer_id, service_id) ──────────

DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN
    SELECT DISTINCT tc.constraint_name
    FROM information_schema.table_constraints tc
    JOIN information_schema.key_column_usage kcu
      ON tc.constraint_name = kcu.constraint_name
     AND kcu.table_schema = 'public'
     AND kcu.table_name   = 'cart_items'
     AND kcu.column_name  = 'customer_id'
    WHERE tc.constraint_type = 'UNIQUE'
      AND tc.table_schema    = 'public'
      AND tc.table_name      = 'cart_items'
  LOOP
    EXECUTE format('ALTER TABLE public.cart_items DROP CONSTRAINT IF EXISTS %I',
                   r.constraint_name);
  END LOOP;
END $$;

-- ── 3. Create new unique index covering all three columns ────────────────────
-- NULLS NOT DISTINCT: two NULL parent_node_id values are treated as equal for
-- conflict detection (PostgreSQL 15+, available in Supabase).

CREATE UNIQUE INDEX IF NOT EXISTS cart_items_customer_service_parent_key
  ON public.cart_items (customer_id, service_id, parent_node_id)
  NULLS NOT DISTINCT;
