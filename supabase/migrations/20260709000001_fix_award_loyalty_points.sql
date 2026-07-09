-- Replace award_loyalty_points() to match current schema:
--   customer_loyalty  : available_points, lifetime_earned, lifetime_redeemed
--   loyalty_transactions : transaction_type
CREATE OR REPLACE FUNCTION award_loyalty_points()
RETURNS TRIGGER AS $$
DECLARE
    s      RECORD;
    earned INTEGER;
BEGIN
    IF NEW.status = 'completed' AND OLD.status <> 'completed' THEN
        SELECT * INTO s FROM loyalty_settings LIMIT 1;
        IF s.is_enabled THEN
            earned := FLOOR(NEW.total_amount / 100) * s.earn_per_100;
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
                    (NEW.customer_id, NEW.id, 'earn',
                     earned, 'Earned for booking #' || LEFT(NEW.id::TEXT, 8));
            END IF;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Recreate the trigger so it binds to the replaced function
DROP TRIGGER IF EXISTS trg_award_loyalty_points ON bookings;
CREATE TRIGGER trg_award_loyalty_points
    AFTER UPDATE ON bookings
    FOR EACH ROW EXECUTE FUNCTION award_loyalty_points();
