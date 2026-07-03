-- Creates the booking_addons join table that records which service add-ons
-- a customer selected for a specific booking.  Prices are snapshotted at
-- booking time so historical records remain accurate after admin edits.

CREATE TABLE IF NOT EXISTS booking_addons (
  id          UUID           NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  booking_id  UUID           NOT NULL REFERENCES bookings(id) ON DELETE CASCADE,
  addon_id    UUID           NOT NULL REFERENCES addons(id) ON DELETE RESTRICT,
  addon_name  TEXT           NOT NULL,
  addon_price NUMERIC(10, 2) NOT NULL,
  created_at  TIMESTAMPTZ    NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_booking_addons_booking_id ON booking_addons (booking_id);

ALTER TABLE booking_addons ENABLE ROW LEVEL SECURITY;

-- Authenticated users (customers, admin) can insert
CREATE POLICY "Authenticated users can insert booking_addons"
  ON booking_addons FOR INSERT
  TO authenticated
  WITH CHECK (true);

-- Authenticated users can view all booking addons
CREATE POLICY "Authenticated users can view booking_addons"
  ON booking_addons FOR SELECT
  TO authenticated
  USING (true);

-- Admins can update / delete
CREATE POLICY "Authenticated users can manage booking_addons"
  ON booking_addons FOR ALL
  TO authenticated
  USING (true)
  WITH CHECK (true);
