-- ─────────────────────────────────────────────────────────────────────────────
-- Extend wallet_transactions type and reference_type enums for refund support
--
-- Adds 'refund_adjustment' to the type CHECK so that a voluntary vendor wallet
-- deduction (Admin-authorised commission claw-back) can be recorded with its
-- own distinct type, separate from the penalty workflow.
--
-- Adds 'refund_request' to the reference_type CHECK so that wallet transactions
-- created in response to a refund decision reference the originating ticket.
--
-- NOTE: Automatic commission claw-back is explicitly OUT OF SCOPE.
-- These types are registered now so future manual wallet adjustment RPCs can
-- use them without another schema migration.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── Extend type CHECK ─────────────────────────────────────────────────────────
--
-- 20260803000004 created this constraint with the explicit name
-- wallet_transactions_type_check.  Drop by name (IF EXISTS handles a fresh
-- database where the constraint was never added) and recreate with the full
-- value set, preserving all existing allowed types.
--
-- DO NOT use pg_get_constraintdef() pattern matching here: Postgres normalises
-- CHECK (type IN (...)) to CHECK ((type = ANY (ARRAY[...]))) in the catalog,
-- so 'ILIKE %type%IN%' never matches and the drop is silently skipped.

ALTER TABLE wallet_transactions
  DROP CONSTRAINT IF EXISTS wallet_transactions_type_check;

ALTER TABLE wallet_transactions
  ADD CONSTRAINT wallet_transactions_type_check
    CHECK (type IN (
      'top_up',
      'commission',
      'penalty',
      'adjustment',
      'refund_adjustment'   -- admin-authorised wallet deduction related to a refund
    ));

-- ── Extend reference_type CHECK ───────────────────────────────────────────────
--
-- Same approach: drop by known name, recreate with all values.

ALTER TABLE wallet_transactions
  DROP CONSTRAINT IF EXISTS wallet_transactions_reference_type_check;

ALTER TABLE wallet_transactions
  ADD CONSTRAINT wallet_transactions_reference_type_check
    CHECK (reference_type IN (
      'booking',
      'manual',
      'refund_request'   -- wallet transaction linked to a refund ticket
    ));
