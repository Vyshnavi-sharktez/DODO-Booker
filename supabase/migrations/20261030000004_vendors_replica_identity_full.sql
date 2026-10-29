-- Vendors table: REPLICA IDENTITY FULL for reliable Realtime UPDATE filtering.
--
-- Root cause identical to 20261021000002_bookings_replica_identity_full.sql:
-- With DEFAULT identity only the PK is in old_record for UPDATE/DELETE events.
-- The vendor-app status channel subscribes with filter `id = eq.{vendorId}`.
-- Under DEFAULT identity, Supabase Realtime can drop filtered UPDATE events
-- because the non-PK columns (including is_active) are absent from old_record.
--
-- REPLICA IDENTITY FULL writes every column into old_record so the filter
-- resolves correctly and is_active change events reach the vendor app reliably.

ALTER TABLE public.vendors REPLICA IDENTITY FULL;
