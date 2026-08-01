-- ── AMC Planned Due Date ──────────────────────────────────────────────────────
-- Each AMC visit has a fixed planned due date derived from the contract's
-- start date and service interval using calendar arithmetic.  The admin may
-- schedule the actual service on a different date (service_date), but
-- planned_due_date never changes.
--
-- Formula: planned_due_date =
--   (contract.created_at AT TIME ZONE 'utc')::date
--   + (amc_visit_number - 1) × calendar_interval
--
-- Interval mapping (service_interval on amc_contracts):
--   monthly     → interval '1 month'
--   quarterly   → interval '3 months'
--   half_yearly → interval '6 months'
--   yearly      → interval '1 year'
--   anything else → NULL (planned_due_date remains NULL)
--
-- Calendar arithmetic preserves month-end semantics (e.g. Jan 31 + 1 month
-- = Feb 28/29, not Mar 2/3).

-- ── 1. Helper: return planned date for a single visit ─────────────────────────

create or replace function public._amc_visit_planned_date(
  p_start_date date,
  p_interval   text,
  p_visit_num  int
) returns date
language sql
immutable
as $$
  select case p_interval
    when 'monthly'     then (p_start_date + (p_visit_num - 1) * interval '1 month')::date
    when 'quarterly'   then (p_start_date + (p_visit_num - 1) * interval '3 months')::date
    when 'half_yearly' then (p_start_date + (p_visit_num - 1) * interval '6 months')::date
    when 'yearly'      then (p_start_date + (p_visit_num - 1) * interval '1 year')::date
    else null
  end;
$$;

-- ── 2. Add planned_due_date column ────────────────────────────────────────────

alter table public.bookings
  add column if not exists planned_due_date date;

comment on column public.bookings.planned_due_date
  is 'Fixed planned visit date computed from the contract start date and service interval using calendar arithmetic.  Immutable once set; does not change when admin reschedules via service_date.';

-- ── 3. BEFORE INSERT trigger: auto-populate planned_due_date ─────────────────
-- Fires on every AMC booking insert — initial checkout visit and all
-- trigger-created subsequent visits — so no Flutter code change is required.

create or replace function public.fn_set_amc_planned_due_date()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_start    date;
  v_interval text;
begin
  if new.is_amc
    and new.amc_contract_id is not null
    and new.amc_visit_number is not null
    and new.planned_due_date is null
  then
    select
      (created_at at time zone 'utc')::date,
      service_interval
    into v_start, v_interval
    from public.amc_contracts
    where id = new.amc_contract_id;

    new.planned_due_date :=
      _amc_visit_planned_date(v_start, v_interval, new.amc_visit_number);
  end if;
  return new;
end;
$$;

drop trigger if exists trg_set_amc_planned_due_date on public.bookings;

create trigger trg_set_amc_planned_due_date
  before insert on public.bookings
  for each row
  execute function public.fn_set_amc_planned_due_date();

-- ── 4. Backfill existing AMC bookings ────────────────────────────────────────

update public.bookings b
set planned_due_date = public._amc_visit_planned_date(
  (c.created_at at time zone 'utc')::date,
  c.service_interval,
  b.amc_visit_number
)
from public.amc_contracts c
where b.amc_contract_id = c.id
  and b.is_amc = true
  and b.amc_visit_number is not null
  and b.planned_due_date is null
  and public._amc_visit_planned_date(
    (c.created_at at time zone 'utc')::date,
    c.service_interval,
    b.amc_visit_number
  ) is not null;
