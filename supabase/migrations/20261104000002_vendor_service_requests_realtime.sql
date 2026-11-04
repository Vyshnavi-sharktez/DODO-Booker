-- ── Enable Realtime on vendor_service_requests ───────────────────────────────
--
-- vendor_service_requests is not in the supabase_realtime publication yet.
-- Adding it allows both the vendor app and admin panel to subscribe to live
-- changes (e.g., deletion requests, approve/reject) without manual refresh.
-- ─────────────────────────────────────────────────────────────────────────────

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE vendor_service_requests;
  END IF;
END;
$$;
