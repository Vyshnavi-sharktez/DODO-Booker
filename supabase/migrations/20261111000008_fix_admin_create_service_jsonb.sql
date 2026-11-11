-- Fix: included_items / excluded_items are jsonb columns, not text[].
-- Drop old overloads with TEXT[] signature before replacing.
DROP FUNCTION IF EXISTS admin_create_custom_service(UUID,TEXT,TEXT,NUMERIC,NUMERIC,TEXT,UUID,TEXT,TEXT,NUMERIC,TEXT[],TEXT[],BOOLEAN,INT,TEXT,TEXT,JSONB);
DROP FUNCTION IF EXISTS admin_create_custom_service(UUID,TEXT,TEXT,NUMERIC,NUMERIC,TEXT,UUID,TEXT,TEXT,NUMERIC,TEXT[],TEXT[],BOOLEAN,INT,TEXT,TEXT);

CREATE OR REPLACE FUNCTION admin_create_custom_service(
  p_vendor_id            UUID,
  p_service_name         TEXT,
  p_description          TEXT             DEFAULT NULL,
  p_price                NUMERIC          DEFAULT NULL,
  p_active_price         NUMERIC          DEFAULT NULL,
  p_image_url            TEXT             DEFAULT NULL,
  p_vendor_category_id   UUID             DEFAULT NULL,
  p_pricing_type         TEXT             DEFAULT 'fixed',
  p_discount_type        TEXT             DEFAULT 'none',
  p_discount_value       NUMERIC          DEFAULT 0,
  p_included_items       JSONB            DEFAULT '[]',
  p_excluded_items       JSONB            DEFAULT '[]',
  p_warranty_enabled     BOOLEAN          DEFAULT false,
  p_warranty_days        INT              DEFAULT NULL,
  p_warranty_covers      TEXT             DEFAULT NULL,
  p_warranty_exclusions  TEXT             DEFAULT NULL,
  p_duration_options     JSONB            DEFAULT '[]'
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_new_id   UUID;
  v_opt      JSONB;
  v_attr_id  UUID;
  v_h        INT;
  v_m        INT;
  v_label    TEXT;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM admin_users WHERE auth_user_id = auth.uid() AND is_active = true
  ) THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  INSERT INTO vendor_service_requests (
    vendor_id, service_name, description,
    price, active_price, image_url,
    vendor_category_id, pricing_type,
    discount_type, discount_value,
    included_items, excluded_items,
    warranty_enabled, warranty_days, warranty_covers, warranty_exclusions,
    request_type, status, is_active
  ) VALUES (
    p_vendor_id, p_service_name, p_description,
    p_price, p_active_price, p_image_url,
    p_vendor_category_id, p_pricing_type,
    p_discount_type, p_discount_value,
    COALESCE(p_included_items, '[]'::jsonb),
    COALESCE(p_excluded_items, '[]'::jsonb),
    p_warranty_enabled, p_warranty_days, p_warranty_covers, p_warranty_exclusions,
    'new_service', 'completed', true
  )
  RETURNING id INTO v_new_id;

  FOR v_opt IN SELECT * FROM jsonb_array_elements(p_duration_options)
  LOOP
    v_h := (v_opt->>'duration_minutes')::int / 60;
    v_m := (v_opt->>'duration_minutes')::int % 60;
    v_label := CASE
      WHEN v_h = 0 THEN v_m || ' min'
      WHEN v_m = 0 THEN v_h || ' hr'
      ELSE v_h || ' hr ' || v_m || ' min'
    END;

    INSERT INTO service_attributes (custom_service_id, name, field_type, is_required)
    VALUES (v_new_id, v_label, 'dropdown', false)
    RETURNING id INTO v_attr_id;

    INSERT INTO service_attribute_options (
      attribute_id, option_name, price_adjustment, sort_order,
      discount_type, discount_value
    ) VALUES (
      v_attr_id, v_label,
      (v_opt->>'price')::numeric, 0,
      COALESCE(v_opt->>'discount_type', 'none'),
      COALESCE((v_opt->>'discount_value')::numeric, 0)
    );
  END LOOP;

  RETURN v_new_id;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_create_custom_service(UUID,TEXT,TEXT,NUMERIC,NUMERIC,TEXT,UUID,TEXT,TEXT,NUMERIC,JSONB,JSONB,BOOLEAN,INT,TEXT,TEXT,JSONB) TO authenticated;
