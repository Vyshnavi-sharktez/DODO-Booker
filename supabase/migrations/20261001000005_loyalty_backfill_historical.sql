-- Backfill loyalty points for completed bookings that never received points.
-- Safe to run multiple times: skips any booking that already has a loyalty
-- transaction, so no double-awarding.
--
-- Uses the global earn_per_100 rate (same fallback the trigger uses when
-- booking_items-level config is unavailable).

DO $$
DECLARE
    b      RECORD;
    s      RECORD;
    earned INTEGER;
BEGIN
    SELECT * INTO s FROM loyalty_settings LIMIT 1;

    IF s IS NULL OR NOT s.is_enabled THEN
        RAISE NOTICE 'Loyalty is disabled or not configured — skipping backfill.';
        RETURN;
    END IF;

    FOR b IN
        SELECT bk.id, bk.customer_id, bk.total_amount
        FROM   bookings bk
        WHERE  bk.status = 'completed'
          AND  bk.customer_id IS NOT NULL
          AND  bk.id NOT IN (
                   SELECT lt.booking_id
                   FROM   loyalty_transactions lt
                   WHERE  lt.booking_id IS NOT NULL
               )
    LOOP
        earned := FLOOR(b.total_amount / 100.0) * s.earn_per_100;

        IF earned > 0 THEN
            INSERT INTO customer_loyalty
                (customer_id, available_points, lifetime_earned, lifetime_redeemed)
            VALUES
                (b.customer_id, earned, earned, 0)
            ON CONFLICT (customer_id) DO UPDATE SET
                available_points = customer_loyalty.available_points + earned,
                lifetime_earned  = customer_loyalty.lifetime_earned  + earned,
                updated_at       = NOW();

            INSERT INTO loyalty_transactions
                (customer_id, booking_id, transaction_type, points, description)
            VALUES
                (b.customer_id, b.id, 'EARN', earned,
                 'Backfill: booking #' || LEFT(b.id::TEXT, 8));

            RAISE NOTICE 'Awarded % points to customer % for booking %',
                earned, b.customer_id, b.id;
        END IF;
    END LOOP;
END;
$$;
