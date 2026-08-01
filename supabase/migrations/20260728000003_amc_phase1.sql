-- AMC Phase 1 redesign
-- Creates amc_plans table, extends amc_contracts and bookings,
-- ensures amc_enabled exists on catalog_nodes.

-- ── 1. amc_plans ─────────────────────────────────────────────────────────────

create table if not exists public.amc_plans (
  id               uuid         primary key default gen_random_uuid(),
  service_id       uuid         not null references public.catalog_nodes(id) on delete cascade,
  name             text         not null,
  recurrence       text         not null check (recurrence in ('weekly', 'monthly', 'yearly')),
  num_visits       int          not null check (num_visits > 0),
  price_per_visit  numeric(10,2) not null check (price_per_visit >= 0),
  discount_type    text         check (discount_type in ('percentage', 'fixed')),
  discount_value   numeric(10,2) not null default 0 check (discount_value >= 0),
  -- Stored generated columns — computed once on each write, never sent in payloads.
  original_total   numeric(10,2) generated always as (
    price_per_visit * num_visits
  ) stored,
  discount_amount  numeric(10,2) generated always as (
    case
      when discount_type = 'percentage'
        then round(price_per_visit * num_visits * discount_value / 100.0, 2)
      when discount_type = 'fixed'
        then least(discount_value, price_per_visit * num_visits)
      else 0
    end
  ) stored,
  final_price      numeric(10,2) generated always as (
    price_per_visit * num_visits - case
      when discount_type = 'percentage'
        then round(price_per_visit * num_visits * discount_value / 100.0, 2)
      when discount_type = 'fixed'
        then least(discount_value, price_per_visit * num_visits)
      else 0
    end
  ) stored,
  is_active        boolean      not null default true,
  created_at       timestamptz  not null default now(),
  updated_at       timestamptz  not null default now()
);

create index if not exists idx_amc_plans_service_id on public.amc_plans (service_id);
create index if not exists idx_amc_plans_active     on public.amc_plans (is_active) where is_active;

-- updated_at trigger
create or replace function public.set_amc_plans_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger trg_amc_plans_updated_at
  before update on public.amc_plans
  for each row execute function public.set_amc_plans_updated_at();

-- RLS
alter table public.amc_plans enable row level security;

-- Customer app reads active plans; admin reads all.
create policy "Public read of AMC plans"
  on public.amc_plans for select
  using (true);

create policy "Authenticated users manage AMC plans"
  on public.amc_plans for all
  using  (auth.role() in ('authenticated', 'service_role'))
  with check (auth.role() in ('authenticated', 'service_role'));

-- ── 2. Extend amc_contracts ───────────────────────────────────────────────────

alter table public.amc_contracts
  add column if not exists plan_id           uuid references public.amc_plans(id) on delete set null,
  add column if not exists visits_completed  int          not null default 0,
  add column if not exists discount_type     text         check (discount_type in ('percentage', 'fixed')),
  add column if not exists discount_value    numeric(10,2) not null default 0,
  add column if not exists original_total    numeric(10,2),
  add column if not exists discount_amount   numeric(10,2) not null default 0,
  add column if not exists final_price       numeric(10,2),
  add column if not exists payment_type      text         not null default 'one_time'
                                               check (payment_type in ('one_time', 'emi')),
  add column if not exists last_vendor_id    uuid references public.vendors(id) on delete set null,
  add column if not exists next_visit_date   date,
  add column if not exists address           text,
  add column if not exists latitude          numeric,
  add column if not exists longitude         numeric,
  add column if not exists preferred_time    text;

comment on column public.amc_contracts.plan_id           is 'FK to the amc_plans row at time of purchase.';
comment on column public.amc_contracts.visits_completed  is 'Incremented when each visit booking is marked completed.';
comment on column public.amc_contracts.discount_type     is 'Snapshot of the plan discount type at purchase time.';
comment on column public.amc_contracts.discount_value    is 'Snapshot of the plan discount value at purchase time.';
comment on column public.amc_contracts.original_total    is 'price_per_visit × total_visits, snapshotted at purchase.';
comment on column public.amc_contracts.discount_amount   is 'Computed discount in rupees, snapshotted at purchase.';
comment on column public.amc_contracts.final_price       is 'Amount actually charged (original_total − discount_amount).';
comment on column public.amc_contracts.payment_type      is 'one_time = paid upfront; emi = charged per visit on completion.';
comment on column public.amc_contracts.last_vendor_id    is 'Vendor who completed the most recent visit — preferred for auto-assignment.';
comment on column public.amc_contracts.next_visit_date   is 'Date on which the next visit booking should be created.';

-- ── 3. Add visit number to bookings ──────────────────────────────────────────

alter table public.bookings
  add column if not exists amc_visit_number int;

comment on column public.bookings.amc_visit_number
  is 'Which visit this booking represents within its AMC contract (1-indexed). NULL for non-AMC bookings.';

-- ── 4. Ensure amc_enabled exists on catalog_nodes ────────────────────────────
-- The old per-plan columns (amc_plan_name, amc_price_per_visit, etc.) are
-- deprecated in favour of the amc_plans table but are NOT dropped here because
-- the Customer App still reads them (Phase 2 will migrate it).

alter table public.catalog_nodes
  add column if not exists amc_enabled boolean not null default false;

comment on column public.catalog_nodes.amc_enabled
  is 'Controls whether the AMC section is shown in the Customer App for this service. Plans are configured in amc_plans.';
