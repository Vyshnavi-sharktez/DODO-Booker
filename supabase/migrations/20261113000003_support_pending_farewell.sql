-- Three-step close: pending_close = "anything else?", pending_farewell = farewell sent, awaiting final ack.

ALTER TABLE support_conversations
  ADD COLUMN IF NOT EXISTS pending_farewell BOOLEAN NOT NULL DEFAULT FALSE;
