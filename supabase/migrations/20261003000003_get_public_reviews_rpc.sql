-- Exposes a minimal, anonymised snapshot of high-rated reviews for the home
-- page testimonials section.  Uses SECURITY DEFINER so the function runs as
-- its owner (postgres), bypassing RLS on customer_reviews and customers —
-- no private fields (phone, email, address, booking details) are exposed.
--
-- Only returns:
--   • first-name (full_name truncated in Dart)
--   • optional avatar URL
--   • rating (1-5)
--   • review text
--   • created_at

CREATE OR REPLACE FUNCTION get_public_reviews(p_limit INT DEFAULT 12)
RETURNS TABLE (
  id                UUID,
  customer_name     TEXT,
  customer_avatar_url TEXT,
  rating            INT,
  review_text       TEXT,
  created_at        TIMESTAMPTZ
)
LANGUAGE SQL
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    cr.id,
    c.full_name              AS customer_name,
    c.profile_image_url      AS customer_avatar_url,
    cr.rating::INT           AS rating,
    cr.review_text,
    cr.created_at
  FROM customer_reviews cr
  JOIN customers c ON c.id = cr.customer_id
  WHERE cr.rating >= 4
    AND cr.review_text IS NOT NULL
    AND trim(cr.review_text) <> ''
  ORDER BY cr.created_at DESC
  LIMIT p_limit;
$$;

GRANT EXECUTE ON FUNCTION get_public_reviews(INT) TO anon, authenticated;
