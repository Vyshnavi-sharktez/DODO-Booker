-- Fix: customer_reviews had no uniqueness constraint, allowing duplicate rows
-- per booking_id. getReviewForBooking used .maybeSingle() which throws 406
-- when multiple rows are returned.
--
-- Step 1: remove any duplicates, keeping the most recently created review
--         per booking (one review covers all items in a multi-service booking).
-- Step 2: add UNIQUE(booking_id) — a booking has exactly one review.

DELETE FROM customer_reviews
WHERE id NOT IN (
  SELECT DISTINCT ON (booking_id) id
  FROM customer_reviews
  ORDER BY booking_id, created_at DESC
);

ALTER TABLE customer_reviews
  ADD CONSTRAINT customer_reviews_booking_unique
  UNIQUE (booking_id);
