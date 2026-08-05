-- Migration: 20260805000010_call_sessions_lifecycle.sql
-- Update call_sessions status check constraint for Real-Time Call Lifecycle

ALTER TABLE public.call_sessions
  DROP CONSTRAINT IF EXISTS call_sessions_status_check;

ALTER TABLE public.call_sessions
  ADD CONSTRAINT call_sessions_status_check
  CHECK (status IN ('initiated', 'ringing', 'connected', 'ended', 'missed', 'failed'));

ALTER TABLE public.call_sessions
  ADD COLUMN IF NOT EXISTS duration_seconds INT DEFAULT 0;
