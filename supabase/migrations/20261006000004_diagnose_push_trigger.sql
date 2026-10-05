-- Adds step-level RAISE LOG to fn_send_push_on_notification_insert so each
-- stage of the push delivery chain is visible in Postgres logs.
-- Safe to leave in production — LOG-level messages go to the Postgres log only,
-- never to the client, and never include tokens or secrets.

CREATE OR REPLACE FUNCTION fn_send_push_on_notification_insert()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_push_secret TEXT;
  v_payload     JSONB;
  v_url         TEXT;
BEGIN
  RAISE LOG 'push trigger [1/4]: fired for notification_id=%, user_type=%, user_id=%',
    NEW.id, NEW.user_type, NEW.user_id;

  -- Step 2: read secret from Vault
  SELECT decrypted_secret INTO v_push_secret
  FROM vault.decrypted_secrets
  WHERE name = 'push_function_secret'
  LIMIT 1;

  IF v_push_secret IS NULL OR length(trim(v_push_secret)) = 0 THEN
    RAISE LOG 'push trigger [2/4]: vault secret push_function_secret not configured — skipping notification %', NEW.id;
    RETURN NEW;
  END IF;

  RAISE LOG 'push trigger [2/4]: vault secret present (length=%)', length(v_push_secret);

  -- Step 3: resolve edge function URL
  BEGIN
    v_url := current_setting('app.supabase_url') || '/functions/v1/send-push-notification';
  EXCEPTION WHEN OTHERS THEN
    RAISE LOG 'push trigger [3/4]: app.supabase_url not set (SQLSTATE=%) — cannot call edge function for notification %',
      SQLSTATE, NEW.id;
    RETURN NEW;
  END;

  RAISE LOG 'push trigger [3/4]: edge function URL resolved';

  -- Step 4: fire-and-forget HTTP call via pg_net
  v_payload := jsonb_build_object(
    'notification_id', NEW.id,
    'user_type',       NEW.user_type,
    'user_id',         NEW.user_id,
    'title',           NEW.title,
    'body',            NEW.message,
    'data', jsonb_build_object(
      'notification_id',       NEW.id::TEXT,
      'notification_type',     NEW.notification_type,
      'entity_type',           COALESCE(NEW.entity_type, ''),
      'entity_id',             COALESCE(NEW.entity_id::TEXT, ''),
      'parent_node_id',        COALESCE(NEW.parent_node_id::TEXT, ''),
      'customer_question_id',  COALESCE(NEW.customer_question_id::TEXT, '')
    )
  );

  PERFORM net.http_post(
    url     := v_url,
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer ' || v_push_secret
    ),
    body    := v_payload::TEXT
  );

  RAISE LOG 'push trigger [4/4]: net.http_post queued for notification %', NEW.id;

  RETURN NEW;
EXCEPTION
  WHEN OTHERS THEN
    RAISE LOG 'push trigger: unexpected error for notification %, SQLSTATE=%', NEW.id, SQLSTATE;
    RETURN NEW;
END;
$$;
