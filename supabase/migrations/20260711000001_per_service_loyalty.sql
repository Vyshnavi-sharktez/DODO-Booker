-- ── Per-Service Loyalty Earn Rules ─────────────────────────────────────────────
-- Adds loyalty earn configuration to catalog_nodes so each bookable service
-- can override the global earn rate with a fixed-points or percentage rule.
--
-- New columns on catalog_nodes:
--   loyalty_earn_enabled  — master toggle per service (default true)
--   loyalty_earn_rule     — 'global' | 'fixed' | 'percentage'
--   loyalty_fixed_points  — awarded when rule = 'fixed'
--   loyalty_earn_per_100  — points per ₹100 when rule = 'percentage'
--
-- The award_loyalty_points() trigger is replaced to evaluate each booking_item
-- against its service's earn rule, with a global-rate fallback for services
-- not found in catalog_nodes and a legacy fallback for bookings with no items.


-- ── 1. Add columns to catalog_nodes ────────────────────────────────────────────
ALTER TABLE catalog_nodes
    ADD COLUMN IF NOT EXISTS loyalty_earn_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    ADD COLUMN IF NOT EXISTS loyalty_earn_rule    TEXT    NOT NULL DEFAULT 'global'
        CHECK (loyalty_earn_rule IN ('global', 'fixed', 'percentage')),
    ADD COLUMN IF NOT EXISTS loyalty_fixed_points INTEGER CHECK (loyalty_fixed_points > 0),
    ADD COLUMN IF NOT EXISTS loyalty_earn_per_100 INTEGER CHECK (loyalty_earn_per_100 > 0);


-- ── 2. Refresh catalog_nodes_view to expose the new columns ────────────────────
DROP VIEW IF EXISTS catalog_nodes_view;

CREATE VIEW catalog_nodes_view AS
SELECT
    n.id,
    n.parent_id,
    n.legacy_id,
    n.legacy_type,
    n.name,
    n.slug,
    n.description,
    n.image_url,
    n.icon_key,
    n.sort_order,
    n.is_active,
    n.is_bookable,
    n.base_price,
    n.estimated_duration,
    n.minimum_order_amount,
    n.loyalty_earn_enabled,
    n.loyalty_earn_rule,
    n.loyalty_fixed_points,
    n.loyalty_earn_per_100,
    n.created_at,
    n.updated_at,
    (
        SELECT COUNT(*)::INTEGER
        FROM catalog_nodes c
        WHERE c.parent_id = n.id
          AND c.is_active = TRUE
    ) AS children_count,
    p.name AS parent_name,
    p.slug AS parent_slug
FROM catalog_nodes n
LEFT JOIN catalog_nodes p ON p.id = n.parent_id;


-- ── 3. Replace award_loyalty_points() with per-service earn rule logic ──────────
CREATE OR REPLACE FUNCTION award_loyalty_points()
RETURNS TRIGGER AS $$
DECLARE
    s           RECORD;
    cn          RECORD;
    item_row    RECORD;
    earned      INTEGER := 0;
    item_points INTEGER;
    has_items   BOOLEAN := FALSE;
BEGIN
    IF NEW.status = 'completed' AND OLD.status <> 'completed' THEN
        SELECT * INTO s FROM loyalty_settings LIMIT 1;

        IF s.is_enabled THEN
            FOR item_row IN
                SELECT bi.service_id, bi.total_price
                FROM booking_items bi
                WHERE bi.booking_id = NEW.id
            LOOP
                has_items := TRUE;

                SELECT loyalty_earn_enabled,
                       loyalty_earn_rule,
                       loyalty_fixed_points,
                       loyalty_earn_per_100
                INTO cn
                FROM catalog_nodes
                WHERE id = item_row.service_id;

                IF FOUND THEN
                    IF NOT cn.loyalty_earn_enabled THEN
                        item_points := 0;
                    ELSIF cn.loyalty_earn_rule = 'fixed'
                          AND cn.loyalty_fixed_points IS NOT NULL THEN
                        item_points := cn.loyalty_fixed_points;
                    ELSIF cn.loyalty_earn_rule = 'percentage'
                          AND cn.loyalty_earn_per_100 IS NOT NULL THEN
                        item_points :=
                            FLOOR(item_row.total_price / 100.0) * cn.loyalty_earn_per_100;
                    ELSE
                        -- 'global' or misconfigured override → global rate
                        item_points :=
                            FLOOR(item_row.total_price / 100.0) * s.earn_per_100;
                    END IF;
                ELSE
                    -- Service not in catalog_nodes (legacy) → global rate
                    item_points :=
                        FLOOR(item_row.total_price / 100.0) * s.earn_per_100;
                END IF;

                earned := earned + item_points;
            END LOOP;

            -- Legacy fallback: bookings with no items use total_amount
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
                    (NEW.customer_id, NEW.id, 'earn', earned,
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
