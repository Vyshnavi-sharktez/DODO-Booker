-- Fix: add RECURSIVE keyword to the WITH clause inside check_availability_block.
-- Without it PostgreSQL raises "relation 'ancestors' does not exist" because
-- the self-referencing CTE term is never resolved.

CREATE OR REPLACE FUNCTION check_availability_block(
  p_service_id UUID,
  p_vendor_id  UUID,
  p_date       DATE
)
RETURNS TABLE(
  is_full_day_blocked  BOOLEAN,
  blocked_slots        TEXT[],
  block_reason         TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  WITH RECURSIVE
  -- Walk up from the service node through all ancestor categories.
  ancestors(node_id) AS (
    SELECT r.parent_id
    FROM   catalog_node_relationships r
    WHERE  r.child_id = p_service_id
    UNION
    SELECT r.parent_id
    FROM   catalog_node_relationships r
    INNER JOIN ancestors a ON r.child_id = a.node_id
  ),

  -- All active blocks that cover this (service, vendor, date) combination.
  matched AS (
    SELECT ab.blocked_slots, ab.reason, ab.scope
    FROM   availability_blocks ab
    WHERE  ab.is_enabled = true
      AND  p_date BETWEEN ab.start_date AND ab.end_date
      AND  (
             -- 1. global
             ab.scope = 'global'
             -- 2. vendor
             OR (ab.scope = 'vendor' AND p_vendor_id IS NOT NULL
                 AND ab.vendor_id = p_vendor_id)
             -- 3. service (direct match)
             OR (ab.scope = 'service' AND p_service_id IS NOT NULL
                 AND ab.node_id = p_service_id)
             -- 4. category (service is a descendant of the blocked category)
             OR (ab.scope = 'category' AND p_service_id IS NOT NULL
                 AND ab.node_id IN (SELECT a.node_id FROM ancestors a))
           )
  ),

  -- Aggregate: is any block full-day? Collect partial-day slot union.
  agg AS (
    SELECT
      bool_or(m.blocked_slots IS NULL)                          AS has_full_day,
      array_agg(DISTINCT s ORDER BY s)
        FILTER (WHERE m.blocked_slots IS NOT NULL)              AS partial_slots,
      min(m.reason)                                             AS first_reason
    FROM matched m
    LEFT JOIN LATERAL unnest(m.blocked_slots) s ON true
  )

  SELECT
    agg.has_full_day,
    CASE WHEN agg.has_full_day THEN NULL::TEXT[]
         ELSE COALESCE(agg.partial_slots, '{}')
    END,
    agg.first_reason
  FROM agg;
END;
$$;

GRANT EXECUTE ON FUNCTION check_availability_block(UUID, UUID, DATE) TO anon;
GRANT EXECUTE ON FUNCTION check_availability_block(UUID, UUID, DATE) TO authenticated;
