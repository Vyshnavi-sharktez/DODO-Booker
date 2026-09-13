-- Fix: migration 20260912000003 dropped the wrong constraint name
-- (vendor_service_requests_request_type_check instead of vsr_request_type_check).
-- The original vsr_request_type_check still existed blocking 'edit_service' inserts.
-- Also drop the spurious vendor_service_requests_request_type_check that was added.

ALTER TABLE public.vendor_service_requests
  DROP CONSTRAINT IF EXISTS vsr_request_type_check;

ALTER TABLE public.vendor_service_requests
  DROP CONSTRAINT IF EXISTS vendor_service_requests_request_type_check;

ALTER TABLE public.vendor_service_requests
  ADD CONSTRAINT vsr_request_type_check
  CHECK (request_type IN (
    'new_service', 'price_change', 'delete_service', 'edit_service'
  ));
