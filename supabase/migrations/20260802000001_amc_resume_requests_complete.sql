-- ── AMC Resume Requests — complete setup ──────────────────────────────────────
--
-- Creates amc_resume_requests (idempotent — safe to run even if migration
-- 20260801000003_amc_pause.sql already ran and produced the bare table).
--
-- What this migration adds / ensures:
--   1. Table with correct schema (customer_id TEXT, matches amc_pause_requests)
--   2. Performance indexes on amc_contract_id and (status, created_at)
--   3. Partial unique index — one pending resume per contract at a time
--   4. RLS policies (anon insert / select / update) using CREATE POLICY IF NOT EXISTS
--      equivalent pattern so re-runs are safe
--   5. Realtime publication (error-safe DO block handles "already member" case)
--   6. SECURITY DEFINER trigger: notifies admin on INSERT via notifications table
--      (customer name resolved through amc_contracts → customers FK chain because
--       customer_id on this table is TEXT with no direct customers FK)
--
-- Tables NOT touched: amc_pause_requests, amc_contracts, bookings, customers.

-- ── 1. Table ──────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.amc_resume_requests (
  id                  UUID        NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  amc_contract_id     UUID        NOT NULL
                        REFERENCES public.amc_contracts(id) ON DELETE CASCADE,
  customer_id         TEXT        NOT NULL,          -- UUID string, TEXT matches amc_pause_requests
  reason              TEXT,
  status              TEXT        NOT NULL DEFAULT 'pending'
                        CHECK (status IN ('pending', 'approved', 'rejected', 'cancelled')),
  pause_duration_days INT,                           -- filled by admin on approval
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  resolved_at         TIMESTAMPTZ
);

-- ── 2. Indexes ────────────────────────────────────────────────────────────────

CREATE INDEX IF NOT EXISTS idx_amc_resume_req_contract
  ON public.amc_resume_requests (amc_contract_id);

-- Ordered by created_at so the admin queue (oldest-first for pending) is index-only.
CREATE INDEX IF NOT EXISTS idx_amc_resume_req_status_created
  ON public.amc_resume_requests (status, created_at);

-- Prevent more than one pending resume request per contract at a time.
-- The customer app hides the "Request Resume" button when this index is satisfied.
CREATE UNIQUE INDEX IF NOT EXISTS uq_amc_resume_req_one_pending_per_contract
  ON public.amc_resume_requests (amc_contract_id)
  WHERE status = 'pending';

-- ── 3. RLS ───────────────────────────────────────────────────────────────────

ALTER TABLE public.amc_resume_requests ENABLE ROW LEVEL SECURITY;

-- Policies are created only when absent so this block is re-run–safe.
DO $$
BEGIN

  -- INSERT: customer app (anon) can submit resume requests.
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE  schemaname = 'public'
      AND  tablename  = 'amc_resume_requests'
      AND  policyname = 'amc_resume_requests_anon_insert'
  ) THEN
    EXECUTE '
      CREATE POLICY "amc_resume_requests_anon_insert"
        ON public.amc_resume_requests
        FOR INSERT
        TO anon, authenticated
        WITH CHECK (true)
    ';
  END IF;

  -- SELECT: customer app and admin panel (both use anon key) can read all rows.
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE  schemaname = 'public'
      AND  tablename  = 'amc_resume_requests'
      AND  policyname = 'amc_resume_requests_anon_select'
  ) THEN
    EXECUTE '
      CREATE POLICY "amc_resume_requests_anon_select"
        ON public.amc_resume_requests
        FOR SELECT
        TO anon, authenticated
        USING (true)
    ';
  END IF;

  -- UPDATE: customer app (cancel) and admin panel (approve/reject) both use anon.
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE  schemaname = 'public'
      AND  tablename  = 'amc_resume_requests'
      AND  policyname = 'amc_resume_requests_anon_update'
  ) THEN
    EXECUTE '
      CREATE POLICY "amc_resume_requests_anon_update"
        ON public.amc_resume_requests
        FOR UPDATE
        TO anon, authenticated
        USING (true)
        WITH CHECK (true)
    ';
  END IF;

  -- ALL: service_role unrestricted (admin panel service key, background jobs).
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE  schemaname = 'public'
      AND  tablename  = 'amc_resume_requests'
      AND  policyname = 'amc_resume_requests_service_role_all'
  ) THEN
    EXECUTE '
      CREATE POLICY "amc_resume_requests_service_role_all"
        ON public.amc_resume_requests
        FOR ALL
        TO service_role
        USING (true)
        WITH CHECK (true)
    ';
  END IF;

END $$;

-- ── 4. Realtime ───────────────────────────────────────────────────────────────

-- Wrapped in a DO block so re-running is harmless if the table is already a
-- member of the publication (Postgres raises duplicate_object / 42710).
DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.amc_resume_requests;
EXCEPTION
  WHEN duplicate_object    THEN NULL;  -- 42710: already in publication
  WHEN undefined_object    THEN NULL;  -- publication doesn't exist (test env)
END $$;

-- ── 5. Admin notification trigger ────────────────────────────────────────────
--
-- Fires AFTER INSERT on amc_resume_requests.
-- Writes one 'admin' row to notifications so the admin panel badge increments
-- and the live feed shows the request immediately via Realtime.
--
-- Why SECURITY DEFINER?
--   The caller is the anon role (customer app). SECURITY DEFINER elevates to the
--   function owner so the INSERT into notifications succeeds regardless of the
--   caller's RLS context.  SET search_path = public prevents search-path injection.
--
-- Why join through amc_contracts?
--   customer_id on this table is TEXT (no FK to customers).  The contract row
--   carries customer_id UUID → customers.id, so we resolve the name via that chain.

CREATE OR REPLACE FUNCTION public.fn_notify_admin_amc_resume_requested()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_plan_name     TEXT;
  v_customer_name TEXT;
  v_already_exists BOOLEAN;
BEGIN
  -- Duplicate guard: skip silently if a notification for this request already exists.
  SELECT EXISTS (
    SELECT 1 FROM notifications
    WHERE  entity_type = 'amc_resume_request'
      AND  entity_id   = NEW.id
  ) INTO v_already_exists;

  IF v_already_exists THEN
    RAISE LOG '[DODO][AMCResume] Duplicate notification prevented for request %', NEW.id;
    RETURN NEW;
  END IF;

  -- Resolve plan name + customer name via amc_contracts → customers chain.
  SELECT
    ac.plan_name,
    COALESCE(
      NULLIF(TRIM(cu.full_name), ''),
      cu.phone,
      'A customer'
    )
  INTO v_plan_name, v_customer_name
  FROM   public.amc_contracts ac
  LEFT JOIN public.customers  cu ON cu.id = ac.customer_id
  WHERE  ac.id = NEW.amc_contract_id;

  v_plan_name     := COALESCE(v_plan_name,     'an AMC plan');
  v_customer_name := COALESCE(v_customer_name, 'A customer');

  INSERT INTO public.notifications (
    user_type,
    user_id,
    title,
    message,
    notification_type,
    entity_type,
    entity_id,
    is_read,
    created_at
  ) VALUES (
    'admin',
    NULL,
    'AMC Resume Requested',
    v_customer_name || ' has requested to resume their "' ||
      v_plan_name   || '" AMC membership.' ||
      CASE WHEN NEW.reason IS NOT NULL AND TRIM(NEW.reason) <> ''
           THEN ' Reason: "' || TRIM(NEW.reason) || '".'
           ELSE ''
      END,
    'amc_resume_requested',
    'amc_resume_request',
    NEW.id,         -- UUID column, no ::TEXT cast needed
    FALSE,
    NOW()
  );

  RAISE LOG '[DODO][AMCResume] Admin notification created for resume request % (plan: %)',
    NEW.id, v_plan_name;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_admin_amc_resume_requested
  ON public.amc_resume_requests;

CREATE TRIGGER trg_notify_admin_amc_resume_requested
  AFTER INSERT ON public.amc_resume_requests
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_notify_admin_amc_resume_requested();
