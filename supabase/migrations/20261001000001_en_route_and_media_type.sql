-- Adds media_type column to booking_images to track whether an uploaded file is
-- a photo or a video. All existing rows default to 'photo' (backward-compatible).
-- No RLS or storage changes needed — existing policies are already permissive for
-- the anon role that the Vendor App uses.

ALTER TABLE booking_images
  ADD COLUMN IF NOT EXISTS media_type TEXT NOT NULL DEFAULT 'photo'
    CHECK (media_type IN ('photo', 'video'));
