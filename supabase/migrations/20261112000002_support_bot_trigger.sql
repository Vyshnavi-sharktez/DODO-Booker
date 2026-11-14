-- Support Bot pg_net trigger
-- Calls the support-bot Edge Function directly via pg_net on every customer
-- message INSERT. Bypasses the Supabase webhook UI entirely.
-- pg_net fires asynchronously — does not block the INSERT transaction.

CREATE EXTENSION IF NOT EXISTS pg_net SCHEMA extensions;

CREATE OR REPLACE FUNCTION fn_trigger_support_bot()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  IF NEW.sender_type = 'customer' THEN
    PERFORM net.http_post(
      url     := 'https://qspilpbvcldgelgwwrdr.supabase.co/functions/v1/support-bot',
      body    := jsonb_build_object('type', 'INSERT', 'record', to_jsonb(NEW)),
      headers := jsonb_build_object('Content-Type', 'application/json')
    );
  END IF;
  RETURN NEW;
EXCEPTION
  WHEN OTHERS THEN
    RAISE LOG '[DODO][SupportBot] fn_trigger_support_bot failed for message %: %',
      NEW.id, SQLERRM;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_support_bot ON support_messages;
CREATE TRIGGER trg_support_bot
  AFTER INSERT ON support_messages
  FOR EACH ROW
  EXECUTE FUNCTION fn_trigger_support_bot();
