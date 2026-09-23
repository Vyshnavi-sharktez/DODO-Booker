-- ─────────────────────────────────────────────────────────────────────────────
-- Backfill booking_number for existing bookings
--
-- BACKGROUND
-- The booking_number column is nullable.  New bookings should be assigned a
-- booking_number by the checkout flow, but many existing rows have NULL because
-- the column was added after those bookings were created.
--
-- The Customer App generates a fallback display reference client-side:
--   'BK-' || id.substring(0, 8).toUpperCase()
-- e.g. UUID c86b1c92-... → display ref BK-C86B1C92
--
-- This migration writes that same value into booking_number for every row that
-- currently has NULL (or empty string), so:
--   1. The stored value matches what the customer already sees on every screen.
--   2. The admin panel booking search (which queries booking_number) now finds
--      all existing bookings by their reference.
--   3. No existing references change — the formula is identical to the fallback.
--
-- Safe to run multiple times (WHERE clause prevents overwriting real values).
-- ─────────────────────────────────────────────────────────────────────────────

UPDATE bookings
SET    booking_number = 'BK-' || UPPER(LEFT(id::TEXT, 8))
WHERE  booking_number IS NULL
   OR  TRIM(booking_number) = '';
