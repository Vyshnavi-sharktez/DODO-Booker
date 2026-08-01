-- AMC visit-number uniqueness
-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Remove duplicate (amc_contract_id, amc_visit_number) rows created by
--    pre-fix code. For each duplicate group, keep the booking with the
--    highest status rank (mirrors client _statusRank) and delete the rest.
--    Child rows in booking_items / booking_addons are removed first to
--    satisfy FK constraints.
-- 2. Add a partial UNIQUE index so the DB rejects future duplicates.
--    Partial (WHERE both columns NOT NULL) so non-AMC bookings and bookings
--    without an assigned visit number are unaffected.
-- ─────────────────────────────────────────────────────────────────────────────

-- ─── Step 1: Deduplicate existing rows ───────────────────────────────────────

do $$
declare
  v_dup_ids uuid[];
begin
  select array_agg(id)
  into v_dup_ids
  from (
    select
      id,
      row_number() over (
        partition by amc_contract_id, amc_visit_number
        order by
          -- Keep the booking with the most advanced status.
          -- Matches _statusRank() in the Flutter UI layer.
          case status
            when 'completed'             then 5
            when 'awaiting_verification' then 4
            when 'in_progress'           then 3
            when 'started'               then 3
            when 'assigned'              then 2
            when 'accepted'              then 2
            when 'en_route'              then 2
            when 'pending'               then 1
            else 0
          end desc,
          created_at asc  -- oldest booking wins on equal status
      ) as rn
    from public.bookings
    where amc_contract_id is not null
      and amc_visit_number is not null
  ) ranked
  where rn > 1;

  if v_dup_ids is null or array_length(v_dup_ids, 1) is null then
    raise notice 'AMC dedup: no duplicate visit numbers found — skipping';
    return;
  end if;

  raise notice 'AMC dedup: removing % duplicate booking(s)', array_length(v_dup_ids, 1);

  delete from public.booking_items  where booking_id = any(v_dup_ids);
  delete from public.booking_addons where booking_id = any(v_dup_ids);
  delete from public.bookings       where id         = any(v_dup_ids);

  raise notice 'AMC dedup: done';
end;
$$;

-- ─── Step 2: Partial unique index ────────────────────────────────────────────
-- Non-AMC bookings (amc_contract_id IS NULL) and trigger-created bookings
-- that temporarily lack a visit number (amc_visit_number IS NULL) are not
-- constrained. Every real AMC visit booking that has both columns set must
-- be unique within its contract.

create unique index if not exists uq_amc_contract_visit_number
  on public.bookings (amc_contract_id, amc_visit_number)
  where amc_contract_id is not null
    and amc_visit_number is not null;
