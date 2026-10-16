-- RPC: fetch a single archived booking in Booking.fromMap()-compatible JSONB.
-- Merges flat booking_data with embedded customer/vendor/items relationships
-- matching the _reviewSelect query shape used by the active bookings query.

CREATE OR REPLACE FUNCTION public.admin_fetch_deleted_booking_detail(p_booking_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_archived deleted_bookings%ROWTYPE;
BEGIN
  PERFORM fn_assert_active_admin();

  SELECT * INTO v_archived
    FROM deleted_bookings
   WHERE booking_id = p_booking_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Deleted booking % not found in archive', p_booking_id
      USING ERRCODE = 'P0002';
  END IF;

  RETURN
    v_archived.booking_data
    || jsonb_build_object(
         -- Live customer lookup; falls back to null if customer was deleted
         'customers', (
           SELECT jsonb_build_object('full_name', c.full_name, 'phone', c.phone)
             FROM customers c
            WHERE c.id = (v_archived.booking_data->>'customer_id')::uuid
         ),
         -- Live vendor lookup; preserves archived vendor_id when vendor is gone
         'vendors', CASE
           WHEN v_archived.booking_data->>'vendor_id' IS NULL THEN NULL
           ELSE COALESCE(
             (SELECT jsonb_build_object('id', v.id::text, 'business_name', v.business_name)
                FROM vendors v
               WHERE v.id = (v_archived.booking_data->>'vendor_id')::uuid),
             jsonb_build_object(
               'id',            v_archived.booking_data->>'vendor_id',
               'business_name', NULL
             )
           )
         END,
         -- Archived snapshots for array relations
         'booking_items',    COALESCE(v_archived.booking_items_data,    '[]'::jsonb),
         'booking_addons',   COALESCE(v_archived.booking_addons_data,   '[]'::jsonb),
         'customer_reviews', COALESCE(v_archived.customer_reviews_data, '[]'::jsonb),
         'amc_contracts',    NULL
       );
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_fetch_deleted_booking_detail(UUID) TO authenticated;
