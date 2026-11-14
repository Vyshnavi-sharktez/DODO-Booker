-- Store supabase anon key in settings table so admin can update it without
-- touching code. The trigger reads it at runtime on every invocation.

INSERT INTO settings (setting_key, setting_value)
VALUES ('supabase_anon_key', '')
ON CONFLICT (setting_key) DO NOTHING;

-- Update trigger to read anon key from settings table instead of GUC
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
    SELECT setting_value INTO v_anon_key
    FROM settings
    WHERE setting_key = 'supabase_anon_key';

    IF v_anon_key IS NULL OR v_anon_key = '' THEN
      RAISE LOG '[DODO][SupportBot] supabase_anon_key not set in settings — skipping';
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
