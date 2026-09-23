-- ─────────────────────────────────────────────────────────────────────────────
-- pgTAP tests: refund_transactions.gateway_response column restriction
--
-- Verifies the security invariants enforced by migration 000017.
--
-- Run with:
--   psql "$DATABASE_URL" -f supabase/tests/refund_transaction_column_security_test.sql
-- or via supabase test db (requires pgTAP extension).
--
-- Expected outcome: all tests pass; no gateway_response data returned to
-- anon or authenticated roles.
-- ─────────────────────────────────────────────────────────────────────────────

BEGIN;

SELECT plan(10);

-- ── 1. anon has NO table-level SELECT on refund_transactions ─────────────────
SELECT ok(
  NOT has_table_privilege('anon', 'refund_transactions', 'SELECT'),
  'anon does not hold table-level SELECT on refund_transactions'
);

-- ── 2. authenticated has NO table-level SELECT on refund_transactions ─────────
SELECT ok(
  NOT has_table_privilege('authenticated', 'refund_transactions', 'SELECT'),
  'authenticated does not hold table-level SELECT on refund_transactions'
);

-- ── 3. service_role retains full table-level access ───────────────────────────
SELECT has_table_privilege(
  'service_role', 'refund_transactions', 'SELECT',
  'service_role retains SELECT on refund_transactions'
);

-- ── 4. anon has NO column privilege on gateway_response ───────────────────────
SELECT ok(
  NOT has_column_privilege('anon', 'refund_transactions', 'gateway_response', 'SELECT'),
  'anon has no column-level SELECT on gateway_response'
);

-- ── 5. authenticated has NO column privilege on gateway_response ──────────────
SELECT ok(
  NOT has_column_privilege('authenticated', 'refund_transactions', 'gateway_response', 'SELECT'),
  'authenticated has no column-level SELECT on gateway_response'
);

-- ── 6-9. anon has column-level SELECT on the safe fields ─────────────────────
SELECT has_column_privilege(
  'anon', 'refund_transactions', 'id', 'SELECT',
  'anon can SELECT id'
);
SELECT has_column_privilege(
  'anon', 'refund_transactions', 'amount', 'SELECT',
  'anon can SELECT amount'
);
SELECT has_column_privilege(
  'anon', 'refund_transactions', 'status', 'SELECT',
  'anon can SELECT status'
);
SELECT has_column_privilege(
  'anon', 'refund_transactions', 'gateway_refund_id', 'SELECT',
  'anon can SELECT gateway_refund_id'
);

-- ── 10. authenticated has column-level SELECT on safe fields ──────────────────
SELECT has_column_privilege(
  'authenticated', 'refund_transactions', 'amount', 'SELECT',
  'authenticated can SELECT amount'
);

-- ── Behavioural verification (requires a test row) ────────────────────────────
-- The following block inserts a row as service_role, then attempts to read
-- gateway_response as anon.  The SELECT must fail.
--
-- NOTE: run this block only against a test/local DB, never production.
-- Uncomment if running in an isolated environment.
--
-- DO $$
-- DECLARE
--   v_req_id UUID;
--   v_txn_id UUID;
-- BEGIN
--   -- Minimal fixture: insert a fake refund_request + transaction.
--   -- Assumes service_role can bypass RLS for setup.
--   INSERT INTO refund_requests (
--     id, ticket_number, booking_id, customer_id,
--     requested_amount, payment_method_snapshot, amount_paid_snapshot,
--     status
--   ) VALUES (
--     '00000000-0000-0000-0000-000000000001',
--     'TEST-0001',
--     '00000000-0000-0000-0000-000000000002',
--     '00000000-0000-0000-0000-000000000003',
--     100, 'online', 100, 'submitted'
--   ) ON CONFLICT DO NOTHING
--   RETURNING id INTO v_req_id;
--
--   INSERT INTO refund_transactions (
--     id, refund_request_id, amount, gateway, status, refund_method, initiated_by,
--     gateway_response
--   ) VALUES (
--     '00000000-0000-0000-0000-000000000010',
--     '00000000-0000-0000-0000-000000000001',
--     100, 'razorpay', 'completed', 'original_payment_method',
--     auth.uid(),
--     '{"id":"rfnd_test","amount":10000}'
--   ) ON CONFLICT DO NOTHING;
-- END $$;
--
-- -- Attempt SELECT * as anon — must raise permission_denied.
-- SET ROLE anon;
-- SELECT throws_ok(
--   $$SELECT * FROM refund_transactions LIMIT 1$$,
--   '42501',
--   NULL,
--   'SELECT * as anon raises permission_denied (gateway_response not in column grant)'
-- );
-- RESET ROLE;

SELECT * FROM finish();

ROLLBACK;
