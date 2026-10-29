-- Migration: 20261029000005_subscription_payment_gateway.sql
-- Adds Razorpay gateway tracking columns to vendor_subscription_payments so
-- the verify-subscription-payment Edge Function can do a secure server-side
-- HMAC check before activating a subscription.
--
-- Also adds plan_duration_days to vendor_subscriptions so the verification
-- function can calculate expiry_date without querying subscription_plans or
-- catalog_node_configs (avoids issues if a plan config changes mid-payment).
--
-- Safe to re-run: ADD COLUMN IF NOT EXISTS throughout.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── vendor_subscription_payments ─────────────────────────────────────────────

ALTER TABLE public.vendor_subscription_payments
  ADD COLUMN IF NOT EXISTS gateway            TEXT,
  ADD COLUMN IF NOT EXISTS gateway_order_id   TEXT UNIQUE,
  ADD COLUMN IF NOT EXISTS gateway_payment_id TEXT,
  ADD COLUMN IF NOT EXISTS gateway_signature  TEXT,
  ADD COLUMN IF NOT EXISTS gateway_response   JSONB,
  ADD COLUMN IF NOT EXISTS failure_reason     TEXT;

-- ── vendor_subscriptions ──────────────────────────────────────────────────────
-- Stores the plan duration at purchase time so expiry can be calculated
-- server-side without re-querying subscription_plans or catalog configs.

ALTER TABLE public.vendor_subscriptions
  ADD COLUMN IF NOT EXISTS plan_duration_days INT;
