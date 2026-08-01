-- ── AMC weekly/bi-weekly planned due dates ────────────────────────────────────
-- _amc_visit_planned_date previously had no 'weekly' or 'bi_weekly' branch,
-- causing planned_due_date = NULL for all contracts with those intervals.
-- This migration extends the function and backfills affected rows.

create or replace function public._amc_visit_planned_date(
  p_start_date date,
  p_interval   text,
  p_visit_num  int
) returns date
language sql
immutable
as $$
  select case p_interval
    when 'weekly'       then (p_start_date + (p_visit_num - 1) * interval '1 week')::date
    when 'bi_weekly'    then (p_start_date + (p_visit_num - 1) * interval '2 weeks')::date
    when 'monthly'      then (p_start_date + (p_visit_num - 1) * interval '1 month')::date
    when 'quarterly'    then (p_start_date + (p_visit_num - 1) * interval '3 months')::date
    when 'half_yearly'  then (p_start_date + (p_visit_num - 1) * interval '6 months')::date
    when 'yearly'       then (p_start_date + (p_visit_num - 1) * interval '1 year')::date
    else null
  end;
$$;

-- Backfill existing AMC bookings whose planned_due_date is NULL because the
-- interval was 'weekly' or 'bi_weekly' when they were inserted.
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
  and c.service_interval in ('weekly', 'bi_weekly');
