-- Replace description with items JSONB on InstaHelp activity tables.
-- Each activity now holds a list of individual items (e.g. Kitchen → ["Wiping countertops", ...])
-- instead of a single free-text description.

ALTER TABLE public.instahelp_included_activities
  ADD COLUMN IF NOT EXISTS items JSONB NOT NULL DEFAULT '[]'::jsonb;

ALTER TABLE public.instahelp_excluded_activities
  ADD COLUMN IF NOT EXISTS items JSONB NOT NULL DEFAULT '[]'::jsonb;

ALTER TABLE public.instahelp_included_activities
  DROP COLUMN IF EXISTS description;

ALTER TABLE public.instahelp_excluded_activities
  DROP COLUMN IF EXISTS description;
