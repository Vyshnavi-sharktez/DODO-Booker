-- AMC Sequential Visits
-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Remove extra pre-created pending bookings (artifacts of old
--    _generateRecurringBookings logic that created N booking rows at purchase).
--    Child rows (booking_items, booking_addons) are removed first to satisfy
--    FK constraints. Completed visits and their items are NEVER touched.
-- 2. Backfill amc_visit_number on all remaining AMC bookings.
-- 3. Extend fn_amc_visit_completed to auto-create the next visit booking
--    after each completion.

-- ─── Step 1: Clean up pre-created future pending bookings ────────────────────
-- Identify extra bookings BEFORE deleting anything:
--   "extra" = all pending AMC bookings except the oldest one per contract.
--   The oldest pending booking is the current next visit and must stay.
--   Only status='pending' rows are candidates — completed visit history is safe.
do $$
declare
  v_extra_ids uuid[];
begin
  select array_agg(id)
  into v_extra_ids
  from public.bookings
  where is_amc = true
    and amc_contract_id is not null
    and status = 'pending'
    and id not in (
      -- For each contract, the single oldest pending booking to keep
      select distinct on (amc_contract_id) id
      from public.bookings
      where is_amc = true
        and amc_contract_id is not null
        and status = 'pending'
      order by amc_contract_id, created_at
    );

  if v_extra_ids is null or array_length(v_extra_ids, 1) is null then
    raise notice 'AMC cleanup: no extra pending bookings found — skipping';
    return;
  end if;

  raise notice 'AMC cleanup: removing % pre-created pending booking(s)', array_length(v_extra_ids, 1);

  -- Remove child rows first to satisfy FK constraints.
  -- These rows are duplicated artifacts (same service items copied to each
  -- pre-created future visit) and carry no real booking history.
  delete from public.booking_items  where booking_id = any(v_extra_ids);
  delete from public.booking_addons where booking_id = any(v_extra_ids);

  -- Now remove the empty booking shells
  delete from public.bookings where id = any(v_extra_ids);
end;
$$;

-- ─── Step 2: Backfill amc_visit_number ───────────────────────────────────────
-- Rank all remaining AMC bookings within each contract by creation order.
-- Completed visits get 1..n; the current pending booking follows.
-- Idempotent: re-running produces identical results.
update public.bookings b
set amc_visit_number = r.rn
from (
  select id,
         row_number() over (partition by amc_contract_id order by created_at) as rn
  from public.bookings
  where is_amc = true
    and amc_contract_id is not null
) r
where b.id = r.id;

-- ─── Step 3: Extend trigger to auto-create next visit ────────────────────────
-- Replaces the function from 20260730000003 (trigger itself does not change).
create or replace function public.fn_amc_visit_completed()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_completed  int;
  v_effective  int;
  v_next_num   int;
begin
  -- Count completed visits (AFTER trigger: NEW is already 'completed')
  select count(*) into v_completed
  from public.bookings
  where amc_contract_id = new.amc_contract_id
    and status = 'completed';

  -- Effective total: prefer num_visits snapshot, fall back to total_visits
  select coalesce(num_visits, total_visits, 0) into v_effective
  from public.amc_contracts
  where id = new.amc_contract_id;

  -- Update counter and lifecycle status
  update public.amc_contracts
  set
    visits_completed = v_completed,
    status = case
               when v_effective > 0 and v_completed >= v_effective then 'completed'
               else 'active'
             end,
    updated_at = now()
  where id = new.amc_contract_id;

  -- Auto-create the next visit booking only when:
  --   a) Contract still has remaining visits (v_effective=0 = uncapped)
  --   b) No other active booking already exists for this contract.
  --      This guard prevents double-creation if Step 1 left a pending booking
  --      in place (the oldest pending carries over as the pre-populated
  --      next-visit slot rather than the trigger creating a second one).
  if (v_effective = 0 or v_completed < v_effective)
    and not exists (
      select 1
      from public.bookings
      where amc_contract_id = new.amc_contract_id
        and id <> new.id
        and status not in ('completed', 'cancelled', 'rejected')
    )
  then
    v_next_num := v_completed + 1;

    insert into public.bookings (
      customer_id,
      service_id,
      status,
      subtotal,
      discount_amount,
      total_amount,
      address,
      latitude,
      longitude,
      payment_method,
      payment_status,
      is_amc,
      amc_contract_id,
      amc_plan_name,
      amc_recurrence_interval,
      amc_visit_number,
      completion_otp
    ) values (
      new.customer_id,
      new.service_id,
      'pending',
      new.subtotal,
      0,
      new.subtotal,
      new.address,
      new.latitude,
      new.longitude,
      coalesce(new.payment_method, 'cash'),
      'pending',
      true,
      new.amc_contract_id,
      new.amc_plan_name,
      new.amc_recurrence_interval,
      v_next_num,
      lpad((floor(random() * 900000) + 100000)::bigint::text, 6, '0')
    );
  end if;

  return new;
end;
$$;
