-- ============================================================
-- RPC: get_most_booked_service_ids
-- ============================================================
-- Returns the top N service IDs by all-time booking volume.
-- Used by the customer app "Most Booked" home section.
--
-- Aggregation runs entirely in the database so every
-- booking_items row is counted, regardless of table size.
-- The client no longer needs to fetch raw rows and aggregate
-- in Dart.
--
-- SAFE TO RE-RUN: CREATE OR REPLACE is idempotent.
-- ============================================================

CREATE OR REPLACE FUNCTION get_most_booked_service_ids(p_limit INT DEFAULT 10)
RETURNS TABLE (service_id UUID, booking_count BIGINT)
LANGUAGE SQL
STABLE
AS $$
  SELECT
    bi.service_id,
    COUNT(*)::BIGINT AS booking_count
  FROM  booking_items bi
  WHERE bi.service_id IS NOT NULL
  GROUP BY bi.service_id
  ORDER BY booking_count DESC
  LIMIT p_limit;
$$;
