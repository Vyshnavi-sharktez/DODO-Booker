-- AMC (Annual Maintenance Contract) schema
-- Adds amc_contracts table and extends bookings with AMC tracking columns.

-- ── amc_contracts ─────────────────────────────────────────────────────────────

create table if not exists public.amc_contracts (
  id                  uuid primary key default gen_random_uuid(),
  customer_id         uuid not null references public.customers(id) on delete cascade,
  service_id          uuid not null references public.catalog_nodes(id) on delete restrict,
  service_name        text not null,
  plan_name           text not null,
  recurrence_interval text not null default '',
  price_per_visit     numeric(10,2) not null,
  status              text not null default 'active'
                        check (status in ('active', 'paused', 'completed', 'cancelled')),
  total_visits        int not null default 12,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

-- Updated-at trigger
create or replace function public.set_amc_contracts_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger trg_amc_contracts_updated_at
  before update on public.amc_contracts
  for each row execute function public.set_amc_contracts_updated_at();

-- RLS
alter table public.amc_contracts enable row level security;

create policy "Customers can view their own AMC contracts"
  on public.amc_contracts for select
  using (
    customer_id = (
      select id from public.customers
      where phone = (current_setting('request.jwt.claims', true)::jsonb ->> 'phone')
      limit 1
    )
  );

create policy "Authenticated users can insert AMC contracts"
  on public.amc_contracts for insert
  with check (true);

create policy "Admins can manage AMC contracts"
  on public.amc_contracts for all
  using (auth.role() = 'service_role');

-- ── bookings — AMC columns ────────────────────────────────────────────────────

alter table public.bookings
  add column if not exists is_amc                boolean not null default false,
  add column if not exists amc_plan_name         text,
  add column if not exists amc_recurrence_interval text,
  add column if not exists amc_contract_id       uuid references public.amc_contracts(id) on delete set null;

comment on column public.bookings.is_amc is 'True when this booking was created as part of an AMC contract.';
comment on column public.bookings.amc_plan_name is 'Snapshot of the plan name at booking time.';
comment on column public.bookings.amc_recurrence_interval is 'Human-readable interval string, e.g. "Monthly", "Every 30 Days".';
comment on column public.bookings.amc_contract_id is 'FK to the amc_contracts row that generated this booking.';
