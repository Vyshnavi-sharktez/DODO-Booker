-- ── Push notification trigger ─────────────────────────────────────────────────
-- Fires after every INSERT on notifications.
-- Reads PUSH_FUNCTION_SECRET from Vault (never from ALTER DATABASE / settings).
-- Uses pg_net to call the edge function asynchronously — does not block the
-- INSERT transaction and does not raise on delivery failure.
-- Idempotency is enforced by the edge function via push_deliveries.

CREATE OR REPLACE FUNCTION fn_send_push_on_notification_insert()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_push_secret TEXT;
  v_payload     JSONB;
BEGIN
  -- Read secret from Vault; skip silently if not yet configured
  SELECT decrypted_secret INTO v_push_secret
  FROM vault.decrypted_secrets
  WHERE name = 'push_function_secret'
  LIMIT 1;

  IF v_push_secret IS NULL OR length(trim(v_push_secret)) = 0 THEN
    RAISE LOG 'push trigger: vault secret push_function_secret not configured, skipping notification %', NEW.id;
    RETURN NEW;
  END IF;

  -- Build payload — only non-sensitive routing IDs + title/body
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

  -- Fire-and-forget HTTP call via pg_net
  PERFORM net.http_post(
    url     := current_setting('app.supabase_url', true) || '/functions/v1/send-push-notification',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer ' || v_push_secret
    ),
    body    := v_payload::TEXT
  );

  RETURN NEW;
EXCEPTION
  WHEN OTHERS THEN
    -- Never let push failure block the notification INSERT
    RAISE LOG 'push trigger: unexpected error for notification %, SQLSTATE=%', NEW.id, SQLSTATE;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_send_push_on_notification_insert ON notifications;
CREATE TRIGGER trg_send_push_on_notification_insert
  AFTER INSERT ON notifications
  FOR EACH ROW
  EXECUTE FUNCTION fn_send_push_on_notification_insert();
