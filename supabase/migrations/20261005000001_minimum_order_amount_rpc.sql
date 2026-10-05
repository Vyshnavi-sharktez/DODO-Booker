-- Validates that a cart's subtotal meets the effective minimum order amount
-- for every catalog service. Effective minimum = per-service override when set,
-- otherwise the platform global (min_booking_amount in the settings table).
--
-- Returns JSON: { passed: bool, message: text|null }
-- Called by checkout_service.dart before inserting a booking row.

CREATE OR REPLACE FUNCTION validate_cart_minimum_order(
  p_service_ids  text[],
  p_subtotal     numeric
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_global_min    numeric;
  v_service_id    text;
  v_svc_min       numeric;
  v_effective_min numeric;
BEGIN
  -- Fetch the platform-wide global minimum from settings.
  SELECT COALESCE((setting_value)::numeric, 100)
    INTO v_global_min
    FROM settings
   WHERE setting_key = 'min_booking_amount'
   LIMIT 1;

  -- Fallback when the settings row is absent.
  IF v_global_min IS NULL THEN
    v_global_min := 100;
  END IF;

  FOREACH v_service_id IN ARRAY p_service_ids LOOP
    -- Per-service override: NULL means no override → fall back to global.
    SELECT minimum_order_amount
      INTO v_svc_min
      FROM catalog_nodes
     WHERE id = v_service_id::uuid
     LIMIT 1;

    v_effective_min := COALESCE(v_svc_min, v_global_min);

    IF v_effective_min > 0 AND p_subtotal < v_effective_min THEN
      RETURN json_build_object(
        'passed',  false,
        'message', format(
          'Minimum order amount of ₹%s required. Please add more services to continue.',
          v_effective_min::int
        )
      );
    END IF;
  END LOOP;

  RETURN json_build_object('passed', true, 'message', NULL);
END;
$$;

GRANT EXECUTE ON FUNCTION validate_cart_minimum_order(text[], numeric)
  TO authenticated, anon;
