-- Migration: Add RLS SELECT policy on admin_users
-- Allows an authenticated user to read their own row.
-- Condition: auth.uid() must match the auth_user_id column.

CREATE POLICY "admin_users: authenticated user can read own row"
  ON admin_users
  FOR SELECT
  TO authenticated
  USING (auth.uid() = auth_user_id);
