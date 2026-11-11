-- Migration: Replace preferred_vendor with per-vendor price map on instahelp_financial_config
-- vendor_prices: JSONB map of { vendor_id: price } — empty means use duration pricing for all vendors

ALTER TABLE instahelp_financial_config
  DROP COLUMN IF EXISTS preferred_vendor_id,
  DROP COLUMN IF EXISTS preferred_vendor_price,
  ADD COLUMN IF NOT EXISTS vendor_prices JSONB NOT NULL DEFAULT '{}';
