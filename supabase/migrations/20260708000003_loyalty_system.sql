-- ── Loyalty Settings ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS loyalty_settings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    is_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    earn_per_100 INTEGER NOT NULL DEFAULT 10,
    point_value NUMERIC(10,2) NOT NULL DEFAULT 1.0,
    minimum_redeem_points INTEGER NOT NULL DEFAULT 100,
    max_redeem_percentage NUMERIC(5,2) NOT NULL DEFAULT 20.0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ── Customer Loyalty Balances ───────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS customer_loyalty (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id UUID UNIQUE NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
    available_points INTEGER NOT NULL DEFAULT 0 CHECK (available_points >= 0),
    lifetime_earned INTEGER NOT NULL DEFAULT 0,
    lifetime_redeemed INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ── Loyalty Transaction Log ─────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS loyalty_transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id UUID NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
    booking_id UUID REFERENCES bookings(id) ON DELETE SET NULL,
    transaction_type TEXT NOT NULL CHECK (transaction_type IN ('earn', 'redeem')),
    points INTEGER NOT NULL,
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_loyalty_tx_customer ON loyalty_transactions(customer_id, created_at DESC);

-- ── Default settings row ────────────────────────────────────────────────────────
INSERT INTO loyalty_settings (earn_per_100, minimum_redeem_points, max_redeem_percentage, is_enabled)
SELECT 10, 100, 20.0, TRUE
WHERE NOT EXISTS (SELECT 1 FROM loyalty_settings);

-- ── Trigger: award points on booking completion ─────────────────────────────────
CREATE OR REPLACE FUNCTION award_loyalty_points()
RETURNS TRIGGER AS $$
DECLARE
    s RECORD;
    earned INTEGER;
BEGIN
    IF NEW.status = 'completed' AND OLD.status <> 'completed' THEN
        SELECT * INTO s FROM loyalty_settings LIMIT 1;
        IF s.is_enabled THEN
            earned := FLOOR(NEW.total_amount / 100) * s.earn_per_100;
            IF earned > 0 THEN
                INSERT INTO customer_loyalty (customer_id, available_points, lifetime_earned, lifetime_redeemed)
                VALUES (NEW.customer_id, earned, earned, 0)
                ON CONFLICT (customer_id) DO UPDATE SET
                    available_points = customer_loyalty.available_points + earned,
                    lifetime_earned  = customer_loyalty.lifetime_earned + earned,
                    updated_at       = NOW();

                INSERT INTO loyalty_transactions (customer_id, booking_id, transaction_type, points, description)
                VALUES (NEW.customer_id, NEW.id, 'earn', earned,
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
