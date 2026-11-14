-- Fix: working_days column is JSONB but RPC was inserting INT[] — cast with to_jsonb()
CREATE OR REPLACE FUNCTION admin_accept_instahelp_request(p_request_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_req  vendor_service_requests%ROWTYPE;
  v_data JSONB;
  v_days INT[];
BEGIN
  SELECT * INTO v_req FROM vendor_service_requests WHERE id = p_request_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Request not found: %', p_request_id;
  END IF;
  IF v_req.status <> 'pending' THEN
    RAISE EXCEPTION 'Request is not pending (current status: %)', v_req.status;
  END IF;

  v_data := COALESCE(v_req.request_data, '{}'::JSONB);

  CASE v_req.request_type

    WHEN 'instahelp_new_duration' THEN
      INSERT INTO instahelp_durations (
        mode_id, label, duration_minutes, price,
        discount_type, discount_value, is_active, sort_order,
        slot_start_time, slot_end_time, slot_interval_minutes, max_bookings_per_slot
      ) VALUES (
        v_req.mode_id,
        v_data->>'label',
        (v_data->>'duration_minutes')::INT,
        (v_data->>'price')::NUMERIC,
        COALESCE(v_data->>'discount_type', 'none'),
        COALESCE((v_data->>'discount_value')::NUMERIC, 0),
        COALESCE((v_data->>'is_active')::BOOLEAN, TRUE),
        COALESCE((v_data->>'sort_order')::INT, 0),
        COALESCE(v_data->>'slot_start_time', '08:00')::TIME,
        COALESCE(v_data->>'slot_end_time', '20:00')::TIME,
        COALESCE((v_data->>'slot_interval_minutes')::INT, 60),
        COALESCE((v_data->>'max_bookings_per_slot')::INT, 10)
      );

    WHEN 'instahelp_edit_duration' THEN
      UPDATE instahelp_durations SET
        label                 = v_data->>'label',
        duration_minutes      = (v_data->>'duration_minutes')::INT,
        price                 = (v_data->>'price')::NUMERIC,
        discount_type         = COALESCE(v_data->>'discount_type', 'none'),
        discount_value        = COALESCE((v_data->>'discount_value')::NUMERIC, 0),
        is_active             = COALESCE((v_data->>'is_active')::BOOLEAN, TRUE),
        slot_start_time       = COALESCE(v_data->>'slot_start_time', '08:00')::TIME,
        slot_end_time         = COALESCE(v_data->>'slot_end_time', '20:00')::TIME,
        slot_interval_minutes = COALESCE((v_data->>'slot_interval_minutes')::INT, 60),
        max_bookings_per_slot = COALESCE((v_data->>'max_bookings_per_slot')::INT, 10)
      WHERE id = v_req.instahelp_resource_id;

    WHEN 'instahelp_delete_duration' THEN
      DELETE FROM instahelp_durations WHERE id = v_req.instahelp_resource_id;

    WHEN 'instahelp_new_activity' THEN
      INSERT INTO instahelp_activities (
        mode_id, title, included_items, excluded_items, is_active, sort_order
      ) VALUES (
        v_req.mode_id,
        v_data->>'title',
        COALESCE(v_data->'included_items', '[]'::JSONB),
        COALESCE(v_data->'excluded_items', '[]'::JSONB),
        COALESCE((v_data->>'is_active')::BOOLEAN, TRUE),
        COALESCE((v_data->>'sort_order')::INT, 0)
      );

    WHEN 'instahelp_edit_activity' THEN
      UPDATE instahelp_activities SET
        title          = v_data->>'title',
        included_items = COALESCE(v_data->'included_items', '[]'::JSONB),
        excluded_items = COALESCE(v_data->'excluded_items', '[]'::JSONB),
        is_active      = COALESCE((v_data->>'is_active')::BOOLEAN, TRUE)
      WHERE id = v_req.instahelp_resource_id;

    WHEN 'instahelp_delete_activity' THEN
      DELETE FROM instahelp_activities WHERE id = v_req.instahelp_resource_id;

    WHEN 'instahelp_slot_config' THEN
      SELECT array_agg(x::INT) INTO v_days
      FROM jsonb_array_elements_text(v_data->'working_days') AS x;

      INSERT INTO instahelp_slot_config (
        mode_id, working_days, start_time, end_time,
        slot_interval_minutes, max_bookings_per_slot, is_active
      ) VALUES (
        v_req.mode_id,
        to_jsonb(COALESCE(v_days, ARRAY[1,2,3,4,5])),
        (v_data->>'start_time')::TIME,
        (v_data->>'end_time')::TIME,
        (v_data->>'slot_interval_minutes')::INT,
        (v_data->>'max_bookings_per_slot')::INT,
        COALESCE((v_data->>'is_active')::BOOLEAN, TRUE)
      )
      ON CONFLICT (mode_id) DO UPDATE SET
        working_days          = to_jsonb(COALESCE(v_days, ARRAY[1,2,3,4,5])),
        start_time            = (v_data->>'start_time')::TIME,
        end_time              = (v_data->>'end_time')::TIME,
        slot_interval_minutes = (v_data->>'slot_interval_minutes')::INT,
        max_bookings_per_slot = (v_data->>'max_bookings_per_slot')::INT,
        is_active             = COALESCE((v_data->>'is_active')::BOOLEAN, TRUE);

    WHEN 'instahelp_financial_config' THEN
      INSERT INTO instahelp_financial_config (
        mode_id, gst_percent, surge_fee_enabled, surge_fee_type, surge_fee_value,
        service_charge_enabled, service_charge_type, service_charge_value
      ) VALUES (
        v_req.mode_id,
        COALESCE((v_data->>'gst_percent')::NUMERIC, 0),
        COALESCE((v_data->>'surge_fee_enabled')::BOOLEAN, FALSE),
        COALESCE(v_data->>'surge_fee_type', 'percentage'),
        COALESCE((v_data->>'surge_fee_value')::NUMERIC, 0),
        COALESCE((v_data->>'service_charge_enabled')::BOOLEAN, FALSE),
        COALESCE(v_data->>'service_charge_type', 'percentage'),
        COALESCE((v_data->>'service_charge_value')::NUMERIC, 0)
      )
      ON CONFLICT (mode_id) DO UPDATE SET
        gst_percent            = COALESCE((v_data->>'gst_percent')::NUMERIC, 0),
        surge_fee_enabled      = COALESCE((v_data->>'surge_fee_enabled')::BOOLEAN, FALSE),
        surge_fee_type         = COALESCE(v_data->>'surge_fee_type', 'percentage'),
        surge_fee_value        = COALESCE((v_data->>'surge_fee_value')::NUMERIC, 0),
        service_charge_enabled = COALESCE((v_data->>'service_charge_enabled')::BOOLEAN, FALSE),
        service_charge_type    = COALESCE(v_data->>'service_charge_type', 'percentage'),
        service_charge_value   = COALESCE((v_data->>'service_charge_value')::NUMERIC, 0);

    ELSE
      RAISE EXCEPTION 'Not an InstaHelp request type: %', v_req.request_type;
  END CASE;

  UPDATE vendor_service_requests
    SET status = 'completed', updated_at = NOW()
  WHERE id = p_request_id;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_accept_instahelp_request(UUID) TO authenticated;
