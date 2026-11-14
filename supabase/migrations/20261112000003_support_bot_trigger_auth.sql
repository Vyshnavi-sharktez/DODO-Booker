-- Fix support-bot trigger: add Authorization header using anon key.
-- The anon key is stored as a database parameter via:
--   ALTER DATABASE postgres SET app.anon_key = 'your-anon-key';
-- (run once manually in SQL Editor — anon key is public, safe to store here)

CREATE OR REPLACE FUNCTION fn_trigger_support_bot()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_anon_key TEXT;
BEGIN
  IF NEW.sender_type = 'customer' THEN
    v_anon_key := current_setting('app.anon_key', true);

    IF v_anon_key IS NULL OR v_anon_key = '' THEN
      RAISE LOG '[DODO][SupportBot] app.anon_key not set — skipping bot trigger';
      RETURN NEW;
    END IF;

    PERFORM net.http_post(
      url     := 'https://qspilpbvcldgelgwwrdr.supabase.co/functions/v1/support-bot',
      body    := jsonb_build_object('type', 'INSERT', 'record', to_jsonb(NEW)),
      headers := jsonb_build_object(
        'Content-Type',  'application/json',
        'Authorization', 'Bearer ' || v_anon_key
      )
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
