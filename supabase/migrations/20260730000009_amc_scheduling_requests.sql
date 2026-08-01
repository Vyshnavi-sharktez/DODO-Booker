-- AMC Scheduling Requests
-- Customers tap "Request Next Visit" to signal to admin that scheduling is needed.
-- Admin sees pending requests and schedules (updates the existing pending booking).

create table if not exists amc_scheduling_requests (
  id                uuid        primary key default gen_random_uuid(),
  amc_contract_id   uuid        not null references amc_contracts(id)  on delete cascade,
  booking_id        uuid        references bookings(id) on delete set null,
  customer_id       uuid        not null references customers(id)       on delete cascade,
  status            text        not null default 'pending'
                                check (status in ('pending','scheduled','cancelled')),
  requested_at      timestamptz not null default now(),
  notes             text,
  created_at        timestamptz not null default now()
);

create index if not exists idx_amc_sched_req_contract
  on amc_scheduling_requests(amc_contract_id);

create index if not exists idx_amc_sched_req_status
  on amc_scheduling_requests(status);

-- One pending request per contract at a time.
create unique index if not exists uq_amc_sched_req_pending_contract
  on amc_scheduling_requests(amc_contract_id)
  where status = 'pending';

-- RLS --

alter table amc_scheduling_requests enable row level security;

-- Customers can read and insert their own requests.
create policy "customers_read_own_amc_requests"
  on amc_scheduling_requests for select
  using (
    customer_id = (
      select id from customers
      where phone = (current_setting('request.jwt.claims', true)::jsonb ->> 'phone')
      limit 1
    )
  );

create policy "customers_insert_own_amc_requests"
  on amc_scheduling_requests for insert
  with check (
    customer_id = (
      select id from customers
      where phone = (current_setting('request.jwt.claims', true)::jsonb ->> 'phone')
      limit 1
    )
  );

create policy "customers_update_own_amc_requests"
  on amc_scheduling_requests for update
  using (
    customer_id = (
      select id from customers
      where phone = (current_setting('request.jwt.claims', true)::jsonb ->> 'phone')
      limit 1
    )
  );

-- Admin (service role) has full access via the service key — no RLS needed for admin.
