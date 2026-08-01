-- AMC visit-completion trigger
-- ─────────────────────────────────────────────────────────────────────────────
-- When a booking that belongs to an AMC contract is marked 'completed':
--   1. Recount all completed visits for that contract.
--   2. Update amc_contracts.visits_completed.
--   3. If every purchased visit is done → set contract status = 'completed'.
--      Otherwise keep (or restore) status = 'active'.
-- ─────────────────────────────────────────────────────────────────────────────

create or replace function public.fn_amc_visit_completed()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_completed int;
  v_effective  int;
begin
  -- Count how many visits for this contract are now completed
  -- (the triggering row is already in its new state when AFTER fires)
  select count(*) into v_completed
  from public.bookings
  where amc_contract_id = new.amc_contract_id
    and status = 'completed';

  -- Resolve effective total: prefer num_visits snapshot, fall back to total_visits
  select coalesce(num_visits, total_visits, 0) into v_effective
  from public.amc_contracts
  where id = new.amc_contract_id;

  update public.amc_contracts
  set
    visits_completed = v_completed,
    status = case
               when v_effective > 0 and v_completed >= v_effective then 'completed'
               else 'active'
             end,
    updated_at = now()
  where id = new.amc_contract_id;

  return new;
end;
$$;

-- Drop old trigger first so CREATE OR REPLACE on the function is re-used cleanly
drop trigger if exists trg_amc_visit_completed on public.bookings;

create trigger trg_amc_visit_completed
  after update of status on public.bookings
  for each row
  when (
    new.is_amc = true
    and new.amc_contract_id is not null
    and new.status = 'completed'
    and (old.status is distinct from 'completed')
  )
  execute function public.fn_amc_visit_completed();

-- ── Backfill: fix any existing contracts whose visits_completed / status
--             are stale (e.g. created before this trigger existed).
-- ─────────────────────────────────────────────────────────────────────────────
do $$
declare
  r record;
  v_completed int;
  v_effective  int;
begin
  for r in
    select id, coalesce(num_visits, total_visits, 0) as eff
    from public.amc_contracts
    where status in ('active', 'completed')
  loop
    select count(*) into v_completed
    from public.bookings
    where amc_contract_id = r.id
      and status = 'completed';

    update public.amc_contracts
    set
      visits_completed = v_completed,
      status = case
                 when r.eff > 0 and v_completed >= r.eff then 'completed'
                 else 'active'
               end,
      updated_at = now()
    where id = r.id;
  end loop;
end;
$$;
