-- Recompile fn_send_push_on_notification_insert after pg_net installation.
-- Fixes: body parameter type (was ::TEXT, net.http_post expects jsonb).
-- The CREATE OR REPLACE forces PL/pgSQL to resolve net.http_post afresh.

CREATE OR REPLACE FUNCTION fn_send_push_on_notification_insert()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_push_secret TEXT;
  v_payload     JSONB;
  v_url         TEXT;
BEGIN
  RAISE LOG 'push trigger [1/4]: fired for notification_id=%, user_type=%, user_id=%',
    NEW.id, NEW.user_type, NEW.user_id;

  SELECT decrypted_secret INTO v_push_secret
  FROM vault.decrypted_secrets
  WHERE name = 'push_function_secret'
  LIMIT 1;

  IF v_push_secret IS NULL OR length(trim(v_push_secret)) = 0 THEN
    RAISE LOG 'push trigger [2/4]: vault secret not configured — skipping notification %', NEW.id;
    RETURN NEW;
  END IF;

  RAISE LOG 'push trigger [2/4]: vault secret present (length=%)', length(v_push_secret);

  v_url := COALESCE(
    current_setting('app.supabase_url', true),
    'https://qspilpbvcldgelgwwrdr.supabase.co'
  ) || '/functions/v1/send-push-notification';

  RAISE LOG 'push trigger [3/4]: edge function URL resolved';

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
    body    := v_payload,
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer ' || v_push_secret
    )
  );

  RAISE LOG 'push trigger [4/4]: net.http_post queued for notification %', NEW.id;

  RETURN NEW;
EXCEPTION
  WHEN OTHERS THEN
    RAISE LOG 'push trigger ERROR for notification %, SQLSTATE=%, SQLERRM=%', NEW.id, SQLSTATE, SQLERRM;
    RETURN NEW;
END;
$$;
