-- Consolidate duplicate AMC contracts caused by the historical bug where each
-- AMC visit booking created a new amc_contracts row instead of reusing the
-- existing active one.
--
-- Strategy per (customer_id, service_id, amc_plan_id) group:
--   1. Pick the earliest-created contract as canonical.
--   2. Re-point every booking that references a duplicate to the canonical id.
--   3. Recount visits_completed on the canonical contract.
--   4. Update canonical status to 'completed' if all purchased visits are done.
--   5. Delete the now-empty duplicate contracts.
--
-- Only processes groups where amc_plan_id IS NOT NULL. Contracts without a
-- plan id are edge cases and cannot be safely grouped without risking
-- cross-plan merges.

do $$
declare
  grp          record;
  canonical_id uuid;
  v_completed  int;
  v_effective  int;
begin
  for grp in
    select customer_id, service_id, amc_plan_id
    from public.amc_contracts
    where amc_plan_id is not null
    group by customer_id, service_id, amc_plan_id
    having count(*) > 1
  loop
    -- Oldest contract in this group becomes the canonical record
    select id into canonical_id
    from public.amc_contracts
    where customer_id = grp.customer_id
      and service_id  = grp.service_id
      and amc_plan_id = grp.amc_plan_id
    order by created_at
    limit 1;

    -- Re-point all bookings linked to duplicate contracts to the canonical id
    update public.bookings
    set amc_contract_id = canonical_id
    where amc_contract_id in (
      select id
      from public.amc_contracts
      where customer_id = grp.customer_id
        and service_id  = grp.service_id
        and amc_plan_id = grp.amc_plan_id
        and id <> canonical_id
    );

    -- Recount completed visits now that all bookings are consolidated
    select count(*) into v_completed
    from public.bookings
    where amc_contract_id = canonical_id
      and status = 'completed';

    select coalesce(num_visits, total_visits, 0) into v_effective
    from public.amc_contracts
    where id = canonical_id;

    update public.amc_contracts
    set
      visits_completed = v_completed,
      status = case
                 when v_effective > 0 and v_completed >= v_effective then 'completed'
                 else 'active'
               end,
      updated_at = now()
    where id = canonical_id;

    -- Delete the now-orphaned duplicate contracts
    delete from public.amc_contracts
    where customer_id = grp.customer_id
      and service_id  = grp.service_id
      and amc_plan_id = grp.amc_plan_id
      and id <> canonical_id;

    raise notice 'Consolidated: customer=% plan=% canonical=% visits=%/%',
      grp.customer_id, grp.amc_plan_id, canonical_id, v_completed, v_effective;
  end loop;
end;
$$;
