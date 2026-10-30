-- Re-point vendor_serving_area_assignments.serving_area_id to
-- service_availability_areas instead of vendor_serving_areas.
--
-- service_availability_areas is the single source of truth for where the
-- platform operates. Vendors now select their coverage from that same list
-- instead of from a separate, independently-maintained zone table.
--
-- Existing assignments are cleared because their serving_area_id values are
-- vendor_serving_areas UUIDs that have no counterpart in service_availability_areas.
-- Vendors will re-select their areas from the correct list.

-- ── 1. Drop the old FK (vendor_serving_areas) ────────────────────────────────

ALTER TABLE public.vendor_serving_area_assignments
  DROP CONSTRAINT IF EXISTS vendor_serving_area_assignments_serving_area_id_fkey;

-- ── 2. Clear stale assignments (IDs no longer valid under the new FK) ─────────

DELETE FROM public.vendor_serving_area_assignments;

-- ── 3. Add new FK pointing to service_availability_areas ─────────────────────
--
-- ON DELETE RESTRICT: prevents deleting a service area that vendors have
-- selected (same safety semantics as before with vendor_serving_areas).

ALTER TABLE public.vendor_serving_area_assignments
  ADD CONSTRAINT vendor_serving_area_assignments_serving_area_id_fkey
  FOREIGN KEY (serving_area_id)
  REFERENCES public.service_availability_areas(id)
  ON DELETE RESTRICT;
