-- ── Custom-service commission resolution fix ──────────────────────────────────
--
-- Problem: resolve_catalog_module_config only walks the catalog_nodes tree.
-- When called with p_service_id = NULL (custom-service booking items), it
-- returns NULL immediately and the caller falls back to the global
-- commission_rules — silently ignoring any per-custom-service commission config
-- saved in catalog_node_configs.custom_service_id.
--
-- Fix 1: Add p_custom_service_id UUID DEFAULT NULL to the function.
--   When supplied, the function does a direct lookup in catalog_node_configs
--   WHERE custom_service_id = p_custom_service_id before doing anything else,
--   then returns that config (or NULL if none, so caller still falls back to
--   commission_rules as before).  The existing catalog-tree walk is untouched
--   and all existing callers that omit the new parameter are unaffected.
--
-- Fix 2: Update fn_deduct_commission_on_booking_complete to select
--   booking_items.custom_service_id and pass it to the resolver so that the
--   wallet commission trigger also honours per-custom-service commission rates.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── Fix 1: extend resolve_catalog_module_config ───────────────────────────────

CREATE OR REPLACE FUNCTION resolve_catalog_module_config(
  p_module            TEXT,
  p_service_id        UUID,
  p_parent_id         UUID,
  p_custom_service_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
AS $$
DECLARE
  v_rel_id      UUID;
  v_child_id    UUID := p_service_id;
  v_parent_id   UUID := p_parent_id;
  v_config      JSONB;
  v_rel_count   INT;
  v_next_id     UUID;
  v_next_parent UUID;
BEGIN
  -- Custom-service shortcut: direct lookup, no tree walk needed.
  IF p_custom_service_id IS NOT NULL THEN
    SELECT config
      INTO v_config
      FROM catalog_node_configs
     WHERE module            = p_module
       AND custom_service_id = p_custom_service_id
       AND is_enabled        = true;
    RETURN v_config;  -- NULL when no per-custom-service config → caller falls back
  END IF;

  -- ── Catalog-tree walk (unchanged) ────────────────────────────────────────────

  IF v_parent_id IS NOT NULL THEN
    SELECT id
      INTO v_rel_id
      FROM catalog_node_relationships
     WHERE parent_id = v_parent_id
       AND child_id  = v_child_id;
  END IF;

  LOOP
    IF v_rel_id IS NOT NULL THEN
      SELECT config
        INTO v_config
        FROM catalog_node_configs
       WHERE module          = p_module
         AND relationship_id = v_rel_id
         AND is_enabled      = true;
      IF FOUND THEN RETURN v_config; END IF;
    END IF;

    SELECT config
      INTO v_config
      FROM catalog_node_configs
     WHERE module          = p_module
       AND node_id         = v_child_id
       AND relationship_id IS NULL
       AND is_enabled      = true;
    IF FOUND THEN RETURN v_config; END IF;

    IF v_parent_id IS NULL THEN RETURN NULL; END IF;

    v_child_id  := v_parent_id;
    v_rel_id    := NULL;
    v_parent_id := NULL;

    SELECT COUNT(*) INTO v_rel_count
      FROM catalog_node_relationships
     WHERE child_id = v_child_id;

    IF v_rel_count = 0 THEN
      SELECT config
        INTO v_config
        FROM catalog_node_configs
       WHERE module          = p_module
         AND node_id         = v_child_id
         AND relationship_id IS NULL
         AND is_enabled      = true;
      IF FOUND THEN RETURN v_config; END IF;
      RETURN NULL;

    ELSIF v_rel_count = 1 THEN
      SELECT id, parent_id
        INTO v_next_id, v_next_parent
        FROM catalog_node_relationships
       WHERE child_id = v_child_id;
      v_rel_id    := v_next_id;
      v_parent_id := v_next_parent;

    ELSE
      SELECT config
        INTO v_config
        FROM catalog_node_configs
       WHERE module          = p_module
         AND node_id         = v_child_id
         AND relationship_id IS NULL
         AND is_enabled      = true;
      IF FOUND THEN RETURN v_config; END IF;
      RETURN NULL;
    END IF;
  END LOOP;
END;
$$;

-- ── Fix 2: update wallet commission trigger ───────────────────────────────────

CREATE OR REPLACE FUNCTION fn_deduct_commission_on_booking_complete()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_fallback_type   TEXT;
  v_fallback_value  NUMERIC;
  v_item            RECORD;
  v_scoped_config   JSONB;
  v_item_commission NUMERIC;
  v_commission      NUMERIC(12,2) := 0;
  v_new_balance     NUMERIC;
BEGIN
  IF NEW.vendor_id IS NULL THEN
    RETURN NEW;
  END IF;

  IF EXISTS (
    SELECT 1 FROM wallet_transactions
     WHERE reference_id   = NEW.id
       AND reference_type = 'booking'
       AND type           = 'commission'
  ) THEN
    RETURN NEW;
  END IF;

  SELECT cr.commission_type, cr.commission_value
    INTO v_fallback_type, v_fallback_value
    FROM commission_rules cr
   WHERE cr.is_enabled = true
     AND (
           (cr.rule_type = 'vendor' AND cr.target_id = NEW.vendor_id)
        OR (cr.rule_type = 'global' AND cr.target_id IS NULL)
     )
   ORDER BY CASE cr.rule_type WHEN 'vendor' THEN 1 ELSE 2 END
   LIMIT 1;

  FOR v_item IN
    SELECT bi.service_id,
           bi.catalog_parent_node_id,
           bi.total_price,
           bi.custom_service_id        -- ← NEW
      FROM booking_items bi
     WHERE bi.booking_id = NEW.id
       AND bi.total_price > 0
  LOOP
    v_scoped_config := resolve_catalog_module_config(
      'commission',
      v_item.service_id,
      v_item.catalog_parent_node_id,
      v_item.custom_service_id         -- ← NEW: honours per-custom-service config
    );

    IF v_scoped_config IS NOT NULL THEN
      IF (v_scoped_config->>'commission_type') = 'percentage' THEN
        v_item_commission :=
          v_item.total_price * (v_scoped_config->>'commission_value')::NUMERIC / 100;
      ELSE
        v_item_commission := (v_scoped_config->>'commission_value')::NUMERIC;
      END IF;
    ELSIF v_fallback_type IS NOT NULL THEN
      IF v_fallback_type = 'percentage' THEN
        v_item_commission := v_item.total_price * v_fallback_value / 100;
      ELSE
        v_item_commission := v_fallback_value;
      END IF;
    ELSE
      v_item_commission := 0;
    END IF;

    v_commission := v_commission + GREATEST(v_item_commission, 0);
  END LOOP;

  v_commission := ROUND(v_commission, 2);

  IF v_commission = 0 THEN
    RETURN NEW;
  END IF;

  WITH deduction AS (
    UPDATE vendor_wallets
       SET available_balance = available_balance - v_commission,
           updated_at        = now()
     WHERE vendor_id = NEW.vendor_id
    RETURNING available_balance
  )
  INSERT INTO wallet_transactions (
    vendor_id, type, amount, balance_after,
    reference_id, reference_type, description
  )
  SELECT
    NEW.vendor_id,
    'commission',
    v_commission,
    d.available_balance,
    NEW.id,
    'booking',
    'Commission deducted on booking completion'
  FROM deduction d;

  RETURN NEW;
END;
$$;
