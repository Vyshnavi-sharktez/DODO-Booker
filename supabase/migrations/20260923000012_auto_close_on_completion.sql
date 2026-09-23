-- ─────────────────────────────────────────────────────────────────────────────
-- Auto-close refund ticket on completion
--
-- When any code path (COD one-step, Razorpay webhook, manual mark-complete)
-- transitions a refund ticket to 'completed', the AFTER UPDATE trigger fires
-- and immediately sets status = 'closed'.
--
-- Design decisions:
--   • Silent close: no history entry is written for the transition.
--     The timeline's last entry ('approved → completed' for COD, or
--     'processing → completed' for online) already communicates the outcome.
--     Writing a second entry inside the trigger would appear *before* the
--     completion entry in the timeline (trigger fires before the RPC's own
--     INSERT into refund_status_history), producing an inverted timeline.
--   • No second customer notification: the 'refund_completed' notification
--     fires from the history INSERT in the RPC; the silent close emits nothing.
--   • closed_at is set; closed_by is NULL (system action, no user context).
--   • SECURITY DEFINER so the trigger can UPDATE refund_requests regardless
--     of the calling role's RLS.
--   • EXCEPTION handler: a failure to close must never roll back the parent
--     completion (e.g. transaction marked complete stays complete even if
--     the close UPDATE somehow fails).
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION fn_auto_close_completed_refund()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
BEGIN
  UPDATE refund_requests
     SET status     = 'closed',
         closed_at  = now(),
         updated_at = now()
   WHERE id = NEW.id;
  RETURN NEW;
EXCEPTION
  WHEN OTHERS THEN
    RAISE LOG '[DODO][Refund] fn_auto_close_completed_refund failed for %: %',
      NEW.id, SQLERRM;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_auto_close_completed_refund ON refund_requests;
CREATE TRIGGER trg_auto_close_completed_refund
  AFTER UPDATE ON refund_requests
  FOR EACH ROW
  WHEN (NEW.status = 'completed' AND OLD.status IS DISTINCT FROM 'completed')
  EXECUTE FUNCTION fn_auto_close_completed_refund();
