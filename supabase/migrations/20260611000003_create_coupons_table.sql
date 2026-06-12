-- Migration: Create coupons table for promotional discount codes

CREATE TABLE IF NOT EXISTS coupons (
  id                  UUID          DEFAULT gen_random_uuid() PRIMARY KEY,
  code                TEXT          NOT NULL UNIQUE,
  description         TEXT,
  discount_type       TEXT          NOT NULL CHECK (discount_type IN ('percentage', 'flat')),
  discount_value      NUMERIC(10,2) NOT NULL CHECK (discount_value > 0),
  min_order_amount    NUMERIC(10,2) CHECK (min_order_amount IS NULL OR min_order_amount >= 0),
  max_discount_amount NUMERIC(10,2) CHECK (max_discount_amount IS NULL OR max_discount_amount > 0),
  usage_limit         INTEGER       CHECK (usage_limit IS NULL OR usage_limit > 0),
  used_count          INTEGER       NOT NULL DEFAULT 0 CHECK (used_count >= 0),
  valid_from          DATE,
  valid_to            DATE,
  is_active           BOOLEAN       NOT NULL DEFAULT TRUE,
  created_at          TIMESTAMPTZ   NOT NULL DEFAULT now(),
  updated_at          TIMESTAMPTZ   NOT NULL DEFAULT now(),

  CONSTRAINT chk_percentage_max CHECK (
    discount_type <> 'percentage' OR discount_value <= 100
  ),
  CONSTRAINT chk_valid_dates CHECK (
    valid_from IS NULL OR valid_to IS NULL OR valid_to >= valid_from
  )
);

CREATE INDEX IF NOT EXISTS idx_coupons_code       ON coupons (code);
CREATE INDEX IF NOT EXISTS idx_coupons_is_active  ON coupons (is_active);
CREATE INDEX IF NOT EXISTS idx_coupons_valid_to   ON coupons (valid_to);

-- Auto-update updated_at
CREATE OR REPLACE FUNCTION fn_coupons_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_coupons_updated_at ON coupons;
CREATE TRIGGER trg_coupons_updated_at
  BEFORE UPDATE ON coupons
  FOR EACH ROW EXECUTE FUNCTION fn_coupons_updated_at();

-- RLS
ALTER TABLE coupons ENABLE ROW LEVEL SECURITY;

-- Admin panel users (service_role key bypasses RLS; anon/authenticated policy for admin JWT)
CREATE POLICY "Admin full access" ON coupons
  FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM admin_users
      WHERE admin_users.user_id = auth.uid()
        AND admin_users.is_active = TRUE
    )
  );

-- Customer app: read active, non-expired coupons (for coupon code validation)
CREATE POLICY "Customers read active coupons" ON coupons
  FOR SELECT
  USING (
    is_active = TRUE
    AND (valid_from IS NULL OR valid_from <= CURRENT_DATE)
    AND (valid_to   IS NULL OR valid_to   >= CURRENT_DATE)
  );
