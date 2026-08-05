-- Migration: 20260805000009_call_sessions.sql
-- Create call_sessions table for Phone Number Masking (Call Bridge) Foundation

CREATE TABLE IF NOT EXISTS public.call_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    booking_id UUID NOT NULL REFERENCES public.bookings(id) ON DELETE CASCADE,
    caller_id UUID NOT NULL,
    callee_id UUID NOT NULL,
    caller_role TEXT NOT NULL CHECK (caller_role IN ('customer', 'vendor')),
    virtual_number TEXT NOT NULL DEFAULT '+91-80000-DODO1',
    status TEXT NOT NULL DEFAULT 'initiated' CHECK (status IN ('initiated', 'connected', 'ended', 'failed')),
    initiated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ended_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.call_sessions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow public all access on call_sessions"
    ON public.call_sessions FOR ALL
    USING (true)
    WITH CHECK (true);
