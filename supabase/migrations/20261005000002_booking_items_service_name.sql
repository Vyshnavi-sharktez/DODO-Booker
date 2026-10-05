-- Add service_name snapshot column to booking_items.
-- Stores the name at booking creation time so My Bookings never goes blank
-- even if a catalog_node is renamed, deleted, or the FK join fails.

ALTER TABLE booking_items
  ADD COLUMN IF NOT EXISTS service_name TEXT;

-- Backfill: catalog service rows — join via service_id FK.
UPDATE booking_items bi
SET    service_name = cn.name
FROM   catalog_nodes cn
WHERE  bi.service_id = cn.id
  AND  bi.service_name IS NULL
  AND  cn.name IS NOT NULL
  AND  cn.name <> '';

-- Backfill: custom service rows — join via custom_service_id FK.
UPDATE booking_items bi
SET    service_name = vsr.service_name
FROM   vendor_service_requests vsr
WHERE  bi.custom_service_id = vsr.id
  AND  bi.service_name IS NULL
  AND  vsr.service_name IS NOT NULL
  AND  vsr.service_name <> '';
