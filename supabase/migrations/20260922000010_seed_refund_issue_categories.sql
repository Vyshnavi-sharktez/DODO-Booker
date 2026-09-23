-- ─────────────────────────────────────────────────────────────────────────────
-- Default Refund Issue Categories
--
-- Seed the admin-managed categories table with sensible defaults.
-- Admin can add, edit, reorder, or deactivate these at any time without a
-- code release.  ON CONFLICT DO NOTHING is safe to re-run.
-- ─────────────────────────────────────────────────────────────────────────────

INSERT INTO refund_issue_categories
  (key, label, description, requires_evidence, is_active, sort_order)
VALUES
  ('vendor_no_show',
   'Vendor did not arrive',
   'The assigned professional failed to arrive at the scheduled time.',
   false, true, 10),

  ('service_not_completed',
   'Service not completed',
   'The service was only partially performed or left incomplete.',
   true, true, 20),

  ('poor_service_quality',
   'Poor service quality',
   'The work delivered was below acceptable standards.',
   true, true, 30),

  ('damage_caused',
   'Damage caused by vendor',
   'The professional caused damage to property or belongings.',
   true, true, 40),

  ('wrong_service_provided',
   'Wrong service provided',
   'A different service was delivered than what was booked.',
   true, true, 50),

  ('booking_cancelled_by_customer',
   'Booking cancelled by customer',
   'Customer cancelled the booking and is requesting a refund.',
   false, true, 60),

  ('booking_cancelled_by_vendor',
   'Booking cancelled by vendor',
   'The vendor cancelled the booking.',
   false, true, 70),

  ('overcharged',
   'Overcharged / incorrect amount',
   'The amount charged was more than the agreed booking total.',
   true, true, 80),

  ('duplicate_charge',
   'Duplicate payment',
   'The customer was charged more than once for the same booking.',
   true, true, 90),

  ('other',
   'Other',
   'Any other issue not covered by the categories above.',
   false, true, 100)

ON CONFLICT (key) DO NOTHING;
