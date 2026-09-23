-- ─────────────────────────────────────────────────────────────────────────────
-- Restrict refund_transactions.gateway_response from anon and authenticated
--
-- Problem
-- ───────
-- refund_transactions has a broad anon SELECT policy ("anon_select_refund_
-- transactions", USING true, added in migration 000005).  In Supabase the
-- anon and authenticated roles also hold table-level SELECT granted by the
-- project's default privilege scaffold.  Both factors combined mean any
-- direct PostgREST call — including ?select=* or ?select=gateway_response —
-- returns the raw Razorpay refund payload stored in gateway_response JSONB.
-- No client UI ever reads this column; it exists only for audit and dispute
-- resolution.
--
-- Fix
-- ───
-- 1. REVOKE table-level SELECT on refund_transactions from anon and
--    authenticated.  PostgreSQL column-level grants are ADDITIVE, not
--    subtractive: column restrictions have no effect while a table-level
--    SELECT exists.  The table-level grant must be removed first.
--
-- 2. GRANT column-level SELECT on every column EXCEPT gateway_response to
--    anon and authenticated.
--
-- Result
-- ──────
--   • SELECT *  or  SELECT gateway_response  → permission denied (anon /
--     authenticated).  * expands to include gateway_response before the
--     privilege check; the missing column grant causes the query to fail.
--
--   • SELECT id, amount, status, … (explicit safe columns)
--     → succeeds, subject to existing RLS row-level policies.
--
--   • service_role: completely unaffected.  service_role bypasses RLS and
--     holds its own table-level grants; this migration touches only the anon
--     and authenticated roles.
--
--   • SECURITY DEFINER RPCs (webhook_complete_refund_transaction,
--     admin_mark_refund_transaction_complete, etc.): run as the function
--     owner role (postgres / service_role) — unaffected.
--
-- Application impact
-- ──────────────────
--   • Customer App _fetchTransactions: already queries an explicit column list
--     that excludes gateway_response — no code change needed.
--
--   • Admin Panel fetchTransactions: was using .select() (SELECT *) which
--     silently fetched gateway_response even though RefundTransaction.fromMap
--     never read it.  Updated to an explicit column list in the same PR.
--
--   • Edge Functions / Razorpay webhook: write gateway_response via SECURITY
--     DEFINER RPCs; they do not read through the PostgREST channel —
--     unaffected.
--
-- Why not a view
-- ──────────────
-- Creating a named view and pointing clients at it would require changing
-- every from('refund_transactions') call in both apps.  Column-level grants
-- achieve the same restriction at the privilege layer and require only one
-- query fix in the admin panel.
-- ─────────────────────────────────────────────────────────────────────────────

-- Step 1 ── Remove table-level SELECT so column grants become the sole path.
--
-- This revokes any table-level SELECT that was granted to these roles —
-- whether via GRANT SELECT ON refund_transactions or via
-- ALTER DEFAULT PRIVILEGES … GRANT SELECT ON TABLES.  Explicit table-level
-- revocations on a specific table always take precedence.
REVOKE SELECT ON refund_transactions FROM anon, authenticated;

-- Step 2 ── Grant column-level SELECT on every column except gateway_response.
--
-- This is the complete column list from migration 20260922000005, minus
-- gateway_response.  The grant is identical for both roles; RLS policies
-- (anon_select_refund_transactions, admin_all_refund_transactions, and
-- customer_select_own_refund_transactions) continue to enforce row-level
-- ownership independently.
GRANT SELECT (
  id,
  refund_request_id,
  amount,
  gateway,
  gateway_refund_id,
  status,
  failure_reason,
  refund_method,
  initiated_by,
  initiated_at,
  completed_at,
  metadata,
  created_at,
  updated_at
) ON refund_transactions TO anon, authenticated;
