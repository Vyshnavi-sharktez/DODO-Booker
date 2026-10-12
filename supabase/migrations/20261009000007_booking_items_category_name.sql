-- Add category_name to booking_items for admin-entered custom items.
-- Catalog-backed items (service_id IS NOT NULL) leave this NULL; the category
-- is derivable from the catalog hierarchy.  Custom items (service_id IS NULL)
-- use this column to store the admin-supplied category label.
ALTER TABLE booking_items ADD COLUMN IF NOT EXISTS category_name TEXT;
