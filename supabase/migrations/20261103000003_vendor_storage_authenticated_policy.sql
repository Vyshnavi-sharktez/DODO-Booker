-- ── vendor-requests storage: authenticated-role upload policy ─────────────────
--
-- Context
-- ───────
-- 20260902000001 created the vendor-requests bucket with an `authenticated`
-- upload policy that used auth.uid() as the folder prefix.
-- 20260902000002 dropped that policy and replaced it with an `anon` policy
-- (no folder scoping) because the vendor app had no Supabase auth session at
-- that time.
-- 20261016000002 switched the vendor app to real Phone OTP auth, so vendor
-- requests now run as `authenticated`. The `anon` policy still fires for
-- unauthenticated callers, but authenticated vendors get no INSERT policy
-- and hit a 403.
--
-- Fix
-- ───
-- Add an authenticated INSERT policy scoped to the vendor's own folder.
-- Upload paths use the vendor row UUID (vendors.id), NOT auth.uid(), so the
-- check joins vendors on auth_user_id = auth.uid() to resolve the UUID.
-- The anon policy is preserved for backward compatibility.
-- ─────────────────────────────────────────────────────────────────────────────

DROP POLICY IF EXISTS "vsr_vendor_upload_authenticated" ON storage.objects;

CREATE POLICY "vsr_vendor_upload_authenticated" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'vendor-requests'
    AND (storage.foldername(name))[1] IN (
      SELECT id::TEXT FROM public.vendors WHERE auth_user_id = auth.uid()
    )
  );
