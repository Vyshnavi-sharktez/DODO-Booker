-- Hierarchical service charge resolution.
-- Walks up the catalog_node_relationships tree from each cart item's
-- parent_node_id, finding the nearest ancestor with service_charge enabled.
-- Deduplicates so the same ancestor is only counted once per booking.

CREATE OR REPLACE FUNCTION resolve_service_charge_for_cart(
  p_cart_items JSONB
  -- [{"service_id": "<uuid>", "parent_node_id": "<uuid>|null"}, ...]
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_item       JSONB;
  v_parent_id  UUID;
  v_current_id UUID;
  v_enabled    BOOLEAN;
  v_config     JSONB;
  v_amount     NUMERIC;
  v_resolved   UUID[]  := ARRAY[]::UUID[];
  v_total      NUMERIC := 0;
  v_breakdown  JSONB   := '[]'::JSONB;
BEGIN
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_cart_items)
  LOOP
    v_parent_id := (v_item->>'parent_node_id')::UUID;
    IF v_parent_id IS NULL THEN
      CONTINUE;
    END IF;

    v_current_id := v_parent_id;

    -- Walk up the hierarchy from parent_node_id to root.
    WHILE v_current_id IS NOT NULL LOOP
      -- Check for service_charge config on this node.
      SELECT is_enabled, config
      INTO   v_enabled, v_config
      FROM   catalog_node_configs
      WHERE  node_id = v_current_id
        AND  module  = 'service_charge';

      IF FOUND AND v_enabled THEN
        -- Nearest enabled ancestor found.
        v_amount := COALESCE((v_config->>'amount')::NUMERIC, 0);

        -- Count this ancestor only once across all cart items.
        IF NOT (v_current_id = ANY(v_resolved)) THEN
          v_resolved  := v_resolved || v_current_id;
          v_total     := v_total + v_amount;
          v_breakdown := v_breakdown || jsonb_build_object(
            'ancestor_node_id', v_current_id,
            'amount',           v_amount
          );
        END IF;

        EXIT; -- Do not walk further for this cart item.
      END IF;
      -- Either no config or config with is_enabled=false → walk up.

      -- Move to primary parent (lowest sort_order when multiple parents exist).
      SELECT parent_id
      INTO   v_current_id
      FROM   catalog_node_relationships
      WHERE  child_id = v_current_id
      ORDER  BY sort_order ASC
      LIMIT  1;
      -- If no parent found, v_current_id becomes NULL and WHILE exits.
    END LOOP;
  END LOOP;

  RETURN jsonb_build_object('total', v_total, 'breakdown', v_breakdown);
END;
$$;

GRANT EXECUTE ON FUNCTION resolve_service_charge_for_cart(JSONB) TO anon, authenticated;
