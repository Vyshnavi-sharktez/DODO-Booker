-- AMC Cancellation Workflow
-- Adds a customer-initiated cancellation request that requires admin approval.
-- Status: active → cancellation_requested → cancelled (approved) or active (rejected).

-- ── Extend status check constraint ────────────────────────────────────────────

ALTER TABLE public.amc_contracts
  DROP CONSTRAINT IF EXISTS amc_contracts_status_check;

ALTER TABLE public.amc_contracts
  ADD CONSTRAINT amc_contracts_status_check
  CHECK (status IN ('active', 'paused', 'completed', 'cancelled', 'cancellation_requested'));

-- ── Cancellation request fields ────────────────────────────────────────────────

ALTER TABLE public.amc_contracts
  ADD COLUMN IF NOT EXISTS cancellation_reason       TEXT,
  ADD COLUMN IF NOT EXISTS cancellation_remarks      TEXT,
  ADD COLUMN IF NOT EXISTS cancellation_requested_at TIMESTAMPTZ;

-- ── Admin notification trigger ─────────────────────────────────────────────────
-- Fires when a customer's contract transitions to 'cancellation_requested'.
-- Uses SECURITY DEFINER so the customer (anon role) can write to notifications.

CREATE OR REPLACE FUNCTION public.fn_notify_admin_amc_cancellation_requested()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_customer_name TEXT;
BEGIN
  IF NEW.status = 'cancellation_requested' AND OLD.status <> 'cancellation_requested' THEN
    SELECT COALESCE(NULLIF(TRIM(full_name), ''), phone, 'A customer')
      INTO v_customer_name
      FROM customers
      WHERE id = NEW.customer_id;

    INSERT INTO notifications (
      user_type, user_id, title, message,
      notification_type, is_read, entity_type, entity_id
    ) VALUES (
      'admin',
      NULL,
      'AMC Cancellation Requested',
      COALESCE(v_customer_name, 'A customer') ||
        ' has requested cancellation of their "' || NEW.plan_name || '" AMC contract.' ||
        ' Reason: ' || COALESCE(NEW.cancellation_reason, 'Not specified') || '.',
      'amc_cancellation_requested',
      FALSE,
      'amc_contract',
      NEW.id
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tr_notify_admin_amc_cancellation_requested ON public.amc_contracts;

CREATE TRIGGER tr_notify_admin_amc_cancellation_requested
  AFTER UPDATE ON public.amc_contracts
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_notify_admin_amc_cancellation_requested();

-- ── RLS: allow customers to update cancellation fields on own contracts ─────────
-- Existing anon update policy from 20260730000004 only allows status updates.
-- This extends the permitted columns to include the cancellation fields.
-- (If the policy already covers all columns via 'using true', no change needed.)

DO $$
BEGIN
  -- Drop and recreate the customer update policy to permit cancellation fields.
  -- Safe to run multiple times.
  DROP POLICY IF EXISTS "Customers can update own AMC contract status" ON public.amc_contracts;
  DROP POLICY IF EXISTS "Authenticated users can update AMC contracts" ON public.amc_contracts;
END;
$$;

CREATE POLICY "Customers can update own AMC contract cancellation"
  ON public.amc_contracts
  FOR UPDATE
  USING (
    customer_id = (
      SELECT id FROM public.customers
      WHERE phone = (current_setting('request.jwt.claims', true)::jsonb ->> 'phone')
      LIMIT 1
    )
  )
  WITH CHECK (true);
