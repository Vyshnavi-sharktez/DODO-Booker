-- Migration: Drop superseded overloads of customer_add_refund_message.
--
-- Background:
--   Migration 15 created: customer_add_refund_message(UUID, TEXT, TEXT)
--   Migration 16 created: customer_add_refund_message(UUID, TEXT, TEXT, UUID)
--   Migration 18 created: customer_add_refund_message(UUID, TEXT, TEXT, UUID, TEXT[])
--
-- PostgreSQL function overloading means all three variants coexist.
-- PostgREST inspects pg_catalog.pg_proc when routing /rpc/customer_add_refund_message
-- and returns "Could not choose the best candidate function" when multiple
-- overloads match the named params sent by the client.
--
-- The 5-param variant (migration 18) is the canonical version — it handles
-- anon auth (p_customer_id), multi-image (p_attachment_urls), and the legacy
-- single-attachment path (p_attachment_url). The 3-param and 4-param variants
-- are strict subsets and are no longer needed.
--
-- Dropping them leaves a single, unambiguous candidate for PostgREST to call.

DROP FUNCTION IF EXISTS customer_add_refund_message(UUID, TEXT, TEXT);
DROP FUNCTION IF EXISTS customer_add_refund_message(UUID, TEXT, TEXT, UUID);
