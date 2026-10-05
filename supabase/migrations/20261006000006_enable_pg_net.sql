-- pg_net is required by fn_send_push_on_notification_insert (net.http_post).
-- Without this extension the trigger silently swallows every call.
-- pg_net creates its own "net" schema — do NOT pre-create it.
CREATE EXTENSION IF NOT EXISTS pg_net;
