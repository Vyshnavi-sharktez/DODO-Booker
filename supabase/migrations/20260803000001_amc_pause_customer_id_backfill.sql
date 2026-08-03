-- Backfill customer_id on amc_pause_requests and amc_resume_requests.
--
-- Root cause: the customer app was reading customer_id from SharedPreferences
-- with a '' fallback instead of from the contract row. Rows inserted before the
-- fix have customer_id = '' (or NULL if the NOT NULL constraint was absent).
-- This migration copies customer_id from the parent amc_contracts row.

-- 1. Backfill amc_pause_requests
UPDATE public.amc_pause_requests apr
SET    customer_id = ac.customer_id::TEXT
FROM   public.amc_contracts ac
WHERE  apr.amc_contract_id = ac.id
  AND  ac.customer_id IS NOT NULL
  AND  (apr.customer_id IS NULL OR apr.customer_id = '');

-- 2. Backfill amc_resume_requests
UPDATE public.amc_resume_requests arr
SET    customer_id = ac.customer_id::TEXT
FROM   public.amc_contracts ac
WHERE  arr.amc_contract_id = ac.id
  AND  ac.customer_id IS NOT NULL
  AND  (arr.customer_id IS NULL OR arr.customer_id = '');
