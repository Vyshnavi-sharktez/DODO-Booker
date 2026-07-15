-- vendor_settlement_bookings: explicit booking ↔ settlement linkage.
--
-- UNIQUE(booking_id)        → each booking can be settled exactly once (DB-level guard)
-- ON DELETE RESTRICT        → prevents deletion of a booking after it is settled
-- ON DELETE CASCADE         → removing a settlement batch also removes its junction rows
--
-- booking_gross / commission_amount / net_vendor_amount are snapshots captured at
-- settlement time so that future changes to catalog commission configs never alter
-- historical settled amounts.

CREATE TABLE vendor_settlement_bookings (
  id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  settlement_id     UUID        NOT NULL REFERENCES vendor_settlements(id) ON DELETE CASCADE,
  booking_id        UUID        NOT NULL REFERENCES bookings(id)           ON DELETE RESTRICT,
  booking_gross     NUMERIC(12,2) NOT NULL,
  commission_amount NUMERIC(12,2) NOT NULL,
  net_vendor_amount NUMERIC(12,2) NOT NULL,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (booking_id)
);

CREATE INDEX idx_vsb_settlement ON vendor_settlement_bookings (settlement_id);
CREATE INDEX idx_vsb_booking    ON vendor_settlement_bookings (booking_id);
