-- Vendor deactivation enforcement.
--
-- When a vendor has is_active = false (admin-controlled), they must be blocked
-- from progressing bookings, managing services, and updating their profile.
-- Existing bookings are NOT cancelled — the trigger only fires on UPDATE, so
-- already-assigned rows remain intact.
--
-- Admin operations (service_role JWT) bypass RLS entirely and are never blocked.
-- The auth.uid() / auth.role() guards below distinguish vendor-app callers
-- (authenticated role) from admin callers (service_role).
--
-- Mirrors the existing customer active check:
--   fn_check_customer_active_on_booking (trg_check_customer_active_on_booking)

-- ── 1. Booking status updates by inactive vendors ──────────────────────────────
--
-- Fires BEFORE UPDATE on bookings when the caller is authenticated (vendor app).
-- Blocks status changes (accepted, en_route, in_progress, awaiting_verification,
-- completed, rejected, etc.) if the booking's assigned vendor is inactive.
-- Does NOT fire for admin (service_role bypasses RLS / triggers that check
-- auth.role()).  Also does NOT fire if vendor_id is NULL (unassigned bookings).

CREATE OR REPLACE FUNCTION fn_check_vendor_active_on_booking_update()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Only enforce for authenticated (vendor-app) callers, not service_role.
  IF current_setting('role', true) = 'service_role' THEN
    RETURN NEW;
  END IF;

  -- Only check when a vendor is assigned.
  IF NEW.vendor_id IS NULL THEN
    RETURN NEW;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM vendors
    WHERE id = NEW.vendor_id
      AND is_active = TRUE
  ) THEN
    RAISE EXCEPTION 'Your account has been deactivated. Please contact DODO support.'
      USING ERRCODE = 'P0003';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_check_vendor_active_on_booking_update ON bookings;
CREATE TRIGGER trg_check_vendor_active_on_booking_update
  BEFORE UPDATE ON bookings
  FOR EACH ROW
  EXECUTE FUNCTION fn_check_vendor_active_on_booking_update();

-- ── 2. vendor_services insert / update by inactive vendors ────────────────────
--
-- Blocks an inactive vendor from assigning new services or toggling existing
-- ones. Uses auth_user_id linkage to identify the calling vendor.

CREATE OR REPLACE FUNCTION fn_check_vendor_active_on_vendor_services()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF current_setting('role', true) = 'service_role' THEN
    RETURN NEW;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM vendors
    WHERE id = NEW.vendor_id
      AND is_active = TRUE
  ) THEN
    RAISE EXCEPTION 'Your account has been deactivated. Please contact DODO support.'
      USING ERRCODE = 'P0003';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_check_vendor_active_on_vendor_services ON vendor_services;
CREATE TRIGGER trg_check_vendor_active_on_vendor_services
  BEFORE INSERT OR UPDATE ON vendor_services
  FOR EACH ROW
  EXECUTE FUNCTION fn_check_vendor_active_on_vendor_services();

-- ── 3. vendor_service_requests: add is_active guard to authenticated policies ──
--
-- The existing vsr_vendor_insert_authenticated and vsr_vendor_update_authenticated
-- policies (from 20261030000001_vsr_authenticated_policies.sql) check
-- auth_user_id = auth.uid() but do not check is_active.
-- Drop and recreate them with the additional is_active = TRUE guard.

DROP POLICY IF EXISTS "vsr_vendor_insert_authenticated" ON vendor_service_requests;
CREATE POLICY "vsr_vendor_insert_authenticated" ON vendor_service_requests
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM vendors
      WHERE id = vendor_id
        AND auth_user_id = auth.uid()
        AND is_active = TRUE
    )
  );

DROP POLICY IF EXISTS "vsr_vendor_update_authenticated" ON vendor_service_requests;
CREATE POLICY "vsr_vendor_update_authenticated" ON vendor_service_requests
  FOR UPDATE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM vendors
      WHERE id = vendor_id
        AND auth_user_id = auth.uid()
        AND is_active = TRUE
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM vendors
      WHERE id = vendor_id
        AND auth_user_id = auth.uid()
        AND is_active = TRUE
    )
  );

-- Keep the existing vsr_vendor_select_authenticated policy unchanged —
-- inactive vendors may still read their own service requests.

-- ── 4. vendors self-update: block profile edits by inactive vendors ───────────
--
-- The existing anon_update_vendors policy (20260612000002) is TO anon with
-- USING(true) / WITH CHECK(true) — kept for backward compat with pre-phone-auth
-- clients.  For authenticated-role callers (current vendor app), add a scoped
-- policy that requires both auth_user_id = auth.uid() AND is_active = TRUE.
-- This prevents an inactive vendor from editing their own profile.
-- Admin uses service_role and is never subject to this policy.

DROP POLICY IF EXISTS "authenticated_self_update_vendors" ON vendors;
CREATE POLICY "authenticated_self_update_vendors" ON vendors
  FOR UPDATE TO authenticated
  USING (
    auth_user_id = auth.uid()
    AND is_active = TRUE
  )
  WITH CHECK (
    auth_user_id = auth.uid()
    AND is_active = TRUE
  );
