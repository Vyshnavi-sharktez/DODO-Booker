-- Migration: 20261118000001_fix_vsr_request_type_check.sql
--
-- The instahelp_approval migration (20261113000004) dropped and recreated the
-- vsr_request_type_check constraint but omitted 'slot_config', which is used by
-- the custom-service slot config flow in the vendor app.  This restores it.

DO $$
DECLARE
  cname TEXT;
BEGIN
  SELECT tc.constraint_name INTO cname
  FROM information_schema.table_constraints tc
  WHERE tc.table_name = 'vendor_service_requests'
    AND tc.constraint_type = 'CHECK'
    AND tc.constraint_name ILIKE '%request_type%'
  LIMIT 1;
  IF cname IS NOT NULL THEN
    EXECUTE format('ALTER TABLE vendor_service_requests DROP CONSTRAINT %I', cname);
  END IF;
END $$;

ALTER TABLE vendor_service_requests
  ADD CONSTRAINT vsr_request_type_check CHECK (
    request_type IN (
      'new_service', 'price_change', 'delete_service', 'edit_service',
      'slot_config',
      'instahelp_new_duration', 'instahelp_edit_duration', 'instahelp_delete_duration',
      'instahelp_new_activity', 'instahelp_edit_activity', 'instahelp_delete_activity',
      'instahelp_slot_config', 'instahelp_delete_slot_config', 'instahelp_financial_config'
    )
  );
