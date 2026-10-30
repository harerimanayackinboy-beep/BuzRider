create type payment_status as enum ('pending','paid','failed','refunded');
create type payout_status as enum ('pending','processing','paid','failed');

create table payments (
  id uuid primary key default gen_random_uuid(),
  delivery_id uuid not null references deliveries(id),
  method payment_method not null,
  amount numeric not null,
  currency text not null default 'ZAR',
  status payment_status not null default 'pending',
  gateway_reference text,
  cash_confirmed_by_driver boolean default false,
  cash_owed_to_platform numeric default 0,
  created_at timestamptz not null default now()
);

create table payouts (
  id uuid primary key default gen_random_uuid(),
  driver_id uuid not null references driver_profiles(id),
  amount numeric not null,
  status payout_status not null default 'pending',
  reference text,
  created_at timestamptz not null default now(),
  paid_at timestamptz
);

create table ratings (
  id uuid primary key default gen_random_uuid(),
  delivery_id uuid not null references deliveries(id),
  rater text not null check (rater in ('customer','driver')),
  driver_id uuid not null references driver_profiles(id),
  score int not null check (score between 1 and 5),
  comment text,
  created_at timestamptz not null default now(),
  unique (delivery_id, rater)
);

create table notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users(id) on delete cascade,
  title text not null,
  body text,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create table support_tickets (
  id uuid primary key default gen_random_uuid(),
  driver_id uuid references driver_profiles(id),
  delivery_id uuid references deliveries(id),
  type text not null default 'issue' check (type in ('issue','complaint','dispute')),
  message text not null,
  status text not null default 'open' check (status in ('open','in_progress','resolved')),
  created_at timestamptz not null default now()
);

create table audit_logs (
  id bigserial primary key,
  actor_id uuid,
  action text not null,
  entity text,
  entity_id text,
  details jsonb,
  created_at timestamptz not null default now()
);

alter table payments enable row level security;
alter table payouts enable row level security;
alter table ratings enable row level security;
alter table notifications enable row level security;
alter table support_tickets enable row level security;
alter table audit_logs enable row level security;

create policy admin_all_payments on payments for all using (is_admin()) with check (is_admin());
create policy admin_all_payouts on payouts for all using (is_admin()) with check (is_admin());
create policy admin_all_ratings on ratings for all using (is_admin()) with check (is_admin());
create policy admin_all_notifications on notifications for all using (is_admin()) with check (is_admin());
create policy admin_all_support_tickets on support_tickets for all using (is_admin()) with check (is_admin());
create policy admin_all_audit_logs on audit_logs for all using (is_admin()) with check (is_admin());

create policy driver_payments on payments for select using (
  exists (select 1 from deliveries d where d.id = delivery_id and d.driver_id = auth.uid())
);
create policy driver_payouts on payouts for select using (driver_id = auth.uid());
create policy driver_ratings on ratings for select using (driver_id = auth.uid());
create policy own_notifications on notifications for select using (user_id = auth.uid());
create policy own_notifications_upd on notifications for update using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy own_tickets_select on support_tickets for select using (driver_id = auth.uid());
create policy own_tickets_insert on support_tickets for insert with check (driver_id = auth.uid());
