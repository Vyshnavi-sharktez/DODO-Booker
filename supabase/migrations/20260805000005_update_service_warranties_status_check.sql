-- Migration: Update service_warranties status check constraint and add notes column

-- 1. Drop existing CHECK constraint if present
ALTER TABLE public.service_warranties
  DROP CONSTRAINT IF EXISTS service_warranties_status_check;

-- 2. Add updated CHECK constraint supporting 'Approved' and 'Rejected' statuses
ALTER TABLE public.service_warranties
  ADD CONSTRAINT service_warranties_status_check
  CHECK (status IN ('Active', 'Expired', 'Claimed', 'Approved', 'Rejected'));

-- 3. Add notes column for rejection reasons or administrative comments
ALTER TABLE public.service_warranties
  ADD COLUMN IF NOT EXISTS notes TEXT;
