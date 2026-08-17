-- Add customer_question_id column to notifications table if not exists
ALTER TABLE notifications ADD COLUMN IF NOT EXISTS customer_question_id UUID;
