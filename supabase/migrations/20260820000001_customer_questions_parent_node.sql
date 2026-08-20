-- Store which parent catalog node the customer was browsing when they submitted
-- the question. Required to re-open the exact same service+parent context when
-- the customer taps the "your question was answered" notification.
ALTER TABLE customer_questions
  ADD COLUMN IF NOT EXISTS parent_node_id UUID
    REFERENCES catalog_nodes(id) ON DELETE SET NULL;
