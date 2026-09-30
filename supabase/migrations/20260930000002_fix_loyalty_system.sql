-- ── Fix loyalty system ────────────────────────────────────────────────────────
--
-- Fixes four issues discovered during audit:
--
--  1. loyalty_transactions.transaction_type CHECK constraint allows lowercase
--     ('earn','redeem') but the trigger and redemption code both write uppercase
--     ('EARN','REDEEM').  Drop and recreate the constraint to accept uppercase,
--     and also allow 'ADJUST' for future manual corrections.
--
--  2. loyalty_settings is missing earn_enabled and redeem_enabled columns that
--     the admin panel and customer app read/write.  Add them with default TRUE.
--
--  3. No RLS on loyalty tables.  Enable RLS with open anon policies consistent
--     with the rest of the codebase (app uses anon key, no Supabase Auth session).
--
--  4. award_loyalty_points() trigger does not check earn_enabled.  Rebuild it
--     to skip earning when the global earn_enabled flag is FALSE.

-- ── 1. Fix transaction_type constraint ───────────────────────────────────────

ALTER TABLE loyalty_transactions
  DROP CONSTRAINT IF EXISTS loyalty_transactions_transaction_type_check;

ALTER TABLE loyalty_transactions
  ADD CONSTRAINT loyalty_transactions_transaction_type_check
    CHECK (transaction_type IN ('EARN', 'REDEEM', 'ADJUST'));

-- ── 2. Add missing columns to loyalty_settings ───────────────────────────────

ALTER TABLE loyalty_settings
  ADD COLUMN IF NOT EXISTS earn_enabled   BOOLEAN NOT NULL DEFAULT TRUE,
  ADD COLUMN IF NOT EXISTS redeem_enabled BOOLEAN NOT NULL DEFAULT TRUE;

-- Back-fill the seed row so the admin page reads the new columns immediately.
UPDATE loyalty_settings
SET    earn_enabled   = TRUE,
       redeem_enabled = TRUE
WHERE  earn_enabled IS DISTINCT FROM TRUE
    OR redeem_enabled IS DISTINCT FROM TRUE;

-- ── 3. Enable RLS on loyalty tables ──────────────────────────────────────────
-- Pattern mirrors cart_items (20260616000001): open anon policies because the
-- app uses the anon key with no Supabase Auth session.

ALTER TABLE loyalty_settings    ENABLE ROW LEVEL SECURITY;
ALTER TABLE customer_loyalty    ENABLE ROW LEVEL SECURITY;
ALTER TABLE loyalty_transactions ENABLE ROW LEVEL SECURITY;

-- loyalty_settings — readable by everyone; only service role writes
CREATE POLICY "anon_select_loyalty_settings"
  ON loyalty_settings FOR SELECT TO anon USING (true);
CREATE POLICY "authenticated_select_loyalty_settings"
  ON loyalty_settings FOR SELECT TO authenticated USING (true);
CREATE POLICY "service_role_all_loyalty_settings"
  ON loyalty_settings FOR ALL TO service_role USING (true) WITH CHECK (true);

-- customer_loyalty — open anon read/write (scoped by customer_id in app code)
CREATE POLICY "anon_select_customer_loyalty"
  ON customer_loyalty FOR SELECT TO anon USING (true);
CREATE POLICY "anon_insert_customer_loyalty"
  ON customer_loyalty FOR INSERT TO anon WITH CHECK (true);
CREATE POLICY "anon_update_customer_loyalty"
  ON customer_loyalty FOR UPDATE TO anon USING (true) WITH CHECK (true);
CREATE POLICY "service_role_all_customer_loyalty"
  ON customer_loyalty FOR ALL TO service_role USING (true) WITH CHECK (true);

-- loyalty_transactions — open anon read/write (scoped by customer_id in app code)
CREATE POLICY "anon_select_loyalty_transactions"
  ON loyalty_transactions FOR SELECT TO anon USING (true);
CREATE POLICY "anon_insert_loyalty_transactions"
  ON loyalty_transactions FOR INSERT TO anon WITH CHECK (true);
CREATE POLICY "service_role_all_loyalty_transactions"
  ON loyalty_transactions FOR ALL TO service_role USING (true) WITH CHECK (true);

-- ── 4. Rebuild trigger to respect earn_enabled ────────────────────────────────

CREATE OR REPLACE FUNCTION award_loyalty_points()
RETURNS TRIGGER AS $$
DECLARE
    s           RECORD;
    cn          RECORD;
    item_row    RECORD;
    scoped_cfg  JSONB;
    earned      INTEGER := 0;
    item_points INTEGER;
    has_items   BOOLEAN := FALSE;
BEGIN
    IF NEW.status = 'completed' AND OLD.status <> 'completed' THEN
        SELECT * INTO s FROM loyalty_settings LIMIT 1;

        -- Respect both master switch and earn sub-switch
        IF s.is_enabled AND s.earn_enabled THEN
            FOR item_row IN
                SELECT bi.service_id,
                       bi.total_price,
                       bi.catalog_parent_node_id
                FROM   booking_items bi
                WHERE  bi.booking_id = NEW.id
            LOOP
                has_items := TRUE;

                -- 1. Catalog-scoped resolution via module config
                scoped_cfg := resolve_catalog_module_config(
                    'loyalty',
                    item_row.service_id,
                    item_row.catalog_parent_node_id
                );

                IF scoped_cfg IS NOT NULL THEN
                    IF (scoped_cfg->>'earn_enabled')::BOOLEAN = FALSE THEN
                        item_points := 0;
                    ELSIF scoped_cfg->>'earn_rule' = 'fixed'
                          AND (scoped_cfg->>'fixed_points') IS NOT NULL THEN
                        item_points := (scoped_cfg->>'fixed_points')::INTEGER;
                    ELSIF scoped_cfg->>'earn_rule' = 'percentage'
                          AND (scoped_cfg->>'earn_per_100') IS NOT NULL THEN
                        item_points :=
                            FLOOR(item_row.total_price / 100.0)
                            * (scoped_cfg->>'earn_per_100')::INTEGER;
                    ELSE
                        item_points :=
                            FLOOR(item_row.total_price / 100.0) * s.earn_per_100;
                    END IF;

                ELSE
                    -- 2. Per-node loyalty columns on catalog_nodes
                    SELECT loyalty_earn_enabled,
                           loyalty_earn_rule,
                           loyalty_fixed_points,
                           loyalty_earn_per_100
                    INTO   cn
                    FROM   catalog_nodes
                    WHERE  id = item_row.service_id;

                    IF FOUND THEN
                        IF NOT cn.loyalty_earn_enabled THEN
                            item_points := 0;
                        ELSIF cn.loyalty_earn_rule = 'fixed'
                              AND cn.loyalty_fixed_points IS NOT NULL THEN
                            item_points := cn.loyalty_fixed_points;
                        ELSIF cn.loyalty_earn_rule = 'percentage'
                              AND cn.loyalty_earn_per_100 IS NOT NULL THEN
                            item_points :=
                                FLOOR(item_row.total_price / 100.0)
                                * cn.loyalty_earn_per_100;
                        ELSE
                            -- 3. Global fallback
                            item_points :=
                                FLOOR(item_row.total_price / 100.0) * s.earn_per_100;
                        END IF;
                    ELSE
                        -- 3. Global fallback (service not in catalog_nodes)
                        item_points :=
                            FLOOR(item_row.total_price / 100.0) * s.earn_per_100;
                    END IF;
                END IF;

                earned := earned + item_points;
            END LOOP;

            IF NOT has_items THEN
                earned := FLOOR(NEW.total_amount / 100.0) * s.earn_per_100;
            END IF;

            IF earned > 0 THEN
                INSERT INTO customer_loyalty
                    (customer_id, available_points, lifetime_earned, lifetime_redeemed)
                VALUES
                    (NEW.customer_id, earned, earned, 0)
                ON CONFLICT (customer_id) DO UPDATE SET
                    available_points = customer_loyalty.available_points + earned,
                    lifetime_earned  = customer_loyalty.lifetime_earned  + earned,
                    updated_at       = NOW();

                INSERT INTO loyalty_transactions
                    (customer_id, booking_id, transaction_type, points, description)
                VALUES
                    (NEW.customer_id, NEW.id, 'EARN', earned,
                     'Earned for booking #' || LEFT(NEW.id::TEXT, 8));
            END IF;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_award_loyalty_points ON bookings;
CREATE TRIGGER trg_award_loyalty_points
    AFTER UPDATE ON bookings
    FOR EACH ROW EXECUTE FUNCTION award_loyalty_points();
