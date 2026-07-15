-- Update award_loyalty_points() to use catalog-scoped loyalty config.
--
-- Resolution order per booking_item:
--   1. resolve_catalog_module_config('loyalty', service_id, catalog_parent_node_id)
--      → path-scoped or node-scoped config from catalog_node_configs
--   2. catalog_nodes.loyalty_earn_* columns (existing per-node config, unchanged)
--   3. loyalty_settings global earn_per_100 (existing global fallback, unchanged)
--
-- The trigger signature, table targets (customer_loyalty, loyalty_transactions),
-- and 'EARN' transaction type are preserved exactly.

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

        IF s.is_enabled THEN
            FOR item_row IN
                SELECT bi.service_id,
                       bi.total_price,
                       bi.catalog_parent_node_id
                FROM   booking_items bi
                WHERE  bi.booking_id = NEW.id
            LOOP
                has_items := TRUE;

                -- 1. Catalog-scoped resolution
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
