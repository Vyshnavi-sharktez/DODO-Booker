-- Backfill booking_items.service_name from catalog_nodes where the name was
-- never snapshotted at booking time (historical rows created before the
-- service_name column was written).
--
-- Safety constraints:
--   • Only rows where service_name IS NULL or empty string.
--   • Only rows where service_id IS NOT NULL (known catalog reference).
--   • Joins on service_id = catalog_nodes.id — no match → no update.
--   • NEVER overwrites an existing non-empty service_name.
--   • Does not touch item_name, pricing, service_id, or any other column.

UPDATE booking_items bi
SET    service_name = cn.name
FROM   catalog_nodes cn
WHERE  bi.service_id = cn.id
  AND  bi.service_id IS NOT NULL
  AND  (bi.service_name IS NULL OR bi.service_name = '');
