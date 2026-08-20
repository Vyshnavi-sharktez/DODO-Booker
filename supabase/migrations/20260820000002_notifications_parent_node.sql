-- Carry parent catalog node context through to the notification row so the
-- customer app can open the exact service+parent instance without an extra
-- round-trip to customer_questions at tap time.
ALTER TABLE notifications
  ADD COLUMN IF NOT EXISTS parent_node_id UUID
    REFERENCES catalog_nodes(id) ON DELETE SET NULL;
