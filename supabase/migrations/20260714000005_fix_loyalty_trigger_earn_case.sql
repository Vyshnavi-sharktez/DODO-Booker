-- Fix award_loyalty_points() to use 'EARN' (uppercase) to match the live
-- CHECK constraint on loyalty_transactions.transaction_type which allows
-- ('EARN', 'REDEEM', 'ADJUST') — all uppercase.
--
-- The constraint was modified in the Supabase dashboard after the original
-- migration ran. The function was never updated to match, causing SQLSTATE
-- 23514 on every OTP booking completion.

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
                        item_points :=
                            FLOOR(item_row.total_price / 100.0) * s.earn_per_100;
                    END IF;
                ELSE
                    item_points :=
                        FLOOR(item_row.total_price / 100.0) * s.earn_per_100;
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
