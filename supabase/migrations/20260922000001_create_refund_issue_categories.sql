-- ─────────────────────────────────────────────────────────────────────────────
-- Refund Issue Categories
--
-- Admin-managed lookup table for the types of issues a customer can cite when
-- requesting a refund.  Flutter widgets MUST NOT hardcode these; they must
-- load them from this table at runtime so Admin can add/edit/deactivate
-- categories without a code release.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS refund_issue_categories (
  id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  key               TEXT        NOT NULL UNIQUE,
  label             TEXT        NOT NULL,
  description       TEXT,
  requires_evidence BOOLEAN     NOT NULL DEFAULT true,
  is_active         BOOLEAN     NOT NULL DEFAULT true,
  sort_order        INTEGER     NOT NULL DEFAULT 0,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_refund_issue_categories_active
  ON refund_issue_categories (is_active, sort_order);

-- ── updated_at trigger ────────────────────────────────────────────────────────

DROP TRIGGER IF EXISTS trg_refund_issue_categories_updated_at
  ON refund_issue_categories;
CREATE TRIGGER trg_refund_issue_categories_updated_at
  BEFORE UPDATE ON refund_issue_categories
  FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at_subscription();

-- ── RLS ───────────────────────────────────────────────────────────────────────

ALTER TABLE refund_issue_categories ENABLE ROW LEVEL SECURITY;

-- Admins: full CRUD (manage categories).
DROP POLICY IF EXISTS "admin_all_refund_issue_categories" ON refund_issue_categories;
CREATE POLICY "admin_all_refund_issue_categories"
  ON refund_issue_categories FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM admin_users
      WHERE admin_users.auth_user_id = auth.uid()
        AND admin_users.is_active = TRUE
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM admin_users
      WHERE admin_users.auth_user_id = auth.uid()
        AND admin_users.is_active = TRUE
    )
  );

-- anon SELECT: customer app needs to display issue categories when raising a
-- ticket.  Only active categories are useful to the customer.
DROP POLICY IF EXISTS "anon_select_active_refund_issue_categories"
  ON refund_issue_categories;
CREATE POLICY "anon_select_active_refund_issue_categories"
  ON refund_issue_categories FOR SELECT
  TO anon
  USING (is_active = TRUE);
