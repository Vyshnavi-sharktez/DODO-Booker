-- Two-step close flow: bot asks for confirmation before closing.
-- pending_close is set true when customer triggers a close keyword.
-- Cleared (false) when customer confirms or denies.

ALTER TABLE support_conversations
  ADD COLUMN IF NOT EXISTS pending_close BOOLEAN NOT NULL DEFAULT FALSE;
