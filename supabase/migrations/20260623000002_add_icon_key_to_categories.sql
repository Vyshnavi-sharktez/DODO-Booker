-- Add icon_key column to categories table.
-- Values are strings that map to Flutter's IconRegistry in the client apps.
-- Admin can update these via the Admin Panel's Category editor.

ALTER TABLE categories ADD COLUMN IF NOT EXISTS icon_key TEXT;

-- Seed icon_key for any existing categories based on their name.
-- These can be overridden in the Admin Panel without a new migration.
UPDATE categories SET icon_key = 'cleaning_services'      WHERE icon_key IS NULL AND lower(name) LIKE '%clean%';
UPDATE categories SET icon_key = 'plumbing'               WHERE icon_key IS NULL AND lower(name) LIKE '%plumb%';
UPDATE categories SET icon_key = 'electrical_services'    WHERE icon_key IS NULL AND lower(name) LIKE '%electr%';
UPDATE categories SET icon_key = 'format_paint'           WHERE icon_key IS NULL AND lower(name) LIKE '%paint%';
UPDATE categories SET icon_key = 'build'                  WHERE icon_key IS NULL AND lower(name) LIKE '%carpen%';
UPDATE categories SET icon_key = 'bug_report'             WHERE icon_key IS NULL AND lower(name) LIKE '%pest%';
UPDATE categories SET icon_key = 'kitchen'                WHERE icon_key IS NULL AND lower(name) LIKE '%appli%';
UPDATE categories SET icon_key = 'local_shipping'         WHERE icon_key IS NULL AND (lower(name) LIKE '%shift%' OR lower(name) LIKE '%moving%');
UPDATE categories SET icon_key = 'content_cut'            WHERE icon_key IS NULL AND (lower(name) LIKE '%salon%' OR lower(name) LIKE '%beauty%');
UPDATE categories SET icon_key = 'yard'                   WHERE icon_key IS NULL AND lower(name) LIKE '%garden%';
UPDATE categories SET icon_key = 'local_laundry_service'  WHERE icon_key IS NULL AND lower(name) LIKE '%laundry%';
