-- ─────────────────────────────────────────────────────────────────────────────
-- Add UNIQUE Constraint to permissions.name
--
-- The permissions table was created without a UNIQUE constraint on the name
-- column, allowing duplicate permission names to be inserted.
--
-- This migration:
--   1. Identifies duplicate names (keeping the oldest row by created_at / id).
--   2. Rewires any role_permissions rows that point to a duplicate onto the
--      kept row, avoiding orphaned assignments.
--   3. Deletes the duplicate rows.
--   4. Adds the UNIQUE constraint.
--
-- Because permissions.id has no created_at, we use the natural sort order of
-- UUID v4 which is random — instead we keep the row with the lexicographically
-- SMALLEST id (consistent tie-breaker) and delete the others.
-- ─────────────────────────────────────────────────────────────────────────────

DO $$
DECLARE
  dup RECORD;
  kept_id   UUID;
  dup_id    UUID;
BEGIN
  -- For each permission name that appears more than once...
  FOR dup IN
    SELECT name
    FROM public.permissions
    GROUP BY name
    HAVING COUNT(*) > 1
  LOOP
    -- Pick the one row to keep (smallest id as stable tie-breaker).
    SELECT id INTO kept_id
    FROM public.permissions
    WHERE name = dup.name
    ORDER BY id
    LIMIT 1;

    -- For every other row with the same name...
    FOR dup_id IN
      SELECT id
      FROM public.permissions
      WHERE name = dup.name
        AND id <> kept_id
    LOOP
      -- Redirect any role_permissions that point to the duplicate.
      -- Use ON CONFLICT DO NOTHING: if the kept_id already has that role,
      -- the duplicate assignment is simply dropped.
      INSERT INTO public.role_permissions (role_id, permissions_id)
        SELECT role_id, kept_id
        FROM public.role_permissions
        WHERE permissions_id = dup_id
      ON CONFLICT DO NOTHING;

      -- Remove role_permissions rows pointing to the duplicate.
      DELETE FROM public.role_permissions WHERE permissions_id = dup_id;

      -- Delete the duplicate permission row.
      DELETE FROM public.permissions WHERE id = dup_id;
    END LOOP;
  END LOOP;
END;
$$;

-- Now that duplicates are gone, the UNIQUE constraint is safe to add.
ALTER TABLE public.permissions
  ADD CONSTRAINT permissions_name_key UNIQUE (name);
