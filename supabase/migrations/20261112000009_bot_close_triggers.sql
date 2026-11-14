-- Bot auto-close: when customer message matches a close trigger, the bot sends
-- a Gemini-generated farewell then sets the conversation status to 'closed'.

ALTER TABLE bot_configs
  ADD COLUMN IF NOT EXISTS close_triggers TEXT NOT NULL DEFAULT
    'that''s all,that''s it,bye,goodbye,no more questions,i''m done,im done,thanks that''s all,thank you that''s all';
