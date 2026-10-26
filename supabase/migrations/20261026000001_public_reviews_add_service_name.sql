-- Extend get_public_reviews to include the service name from the booking.
-- Looks up the first booking_item for the review's booking and returns
-- COALESCE(service_name, item_name).  Returns NULL if the booking or its
-- items have been deleted — callers must handle NULL gracefully.
--
-- Must DROP first because CREATE OR REPLACE cannot change the return type.
DROP FUNCTION IF EXISTS get_public_reviews(INT);

CREATE FUNCTION get_public_reviews(p_limit INT DEFAULT 12)
RETURNS TABLE (
  id                  UUID,
  customer_name       TEXT,
  customer_avatar_url TEXT,
  rating              INT,
  review_text         TEXT,
  created_at          TIMESTAMPTZ,
  service_name        TEXT
)
LANGUAGE SQL
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    cr.id,
    c.full_name                          AS customer_name,
    c.profile_image_url                  AS customer_avatar_url,
    cr.rating::INT                       AS rating,
    cr.review_text,
    cr.created_at,
    (
      SELECT COALESCE(bi.service_name, bi.item_name)
      FROM   booking_items bi
      WHERE  bi.booking_id = cr.booking_id
      LIMIT  1
    )                                    AS service_name
  FROM  customer_reviews cr
  JOIN  customers c ON c.id = cr.customer_id
  WHERE cr.rating >= 4
    AND cr.review_text IS NOT NULL
    AND trim(cr.review_text) <> ''
  ORDER BY cr.created_at DESC
  LIMIT p_limit;
$$;

GRANT EXECUTE ON FUNCTION get_public_reviews(INT) TO anon, authenticated;
