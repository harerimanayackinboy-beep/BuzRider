create type delivery_status as enum ('searching','driver_assigned','driver_arriving','picked_up','in_transit','delivered','cancelled','disputed');
create type payment_method as enum ('cash','online');
create type offer_status as enum ('pending','accepted','declined','expired');

create table pricing_rules (
  id uuid primary key default gen_random_uuid(),
  vehicle_type vehicle_type not null,
  base_fee numeric not null default 0,
  per_km numeric not null default 0,
  per_kg numeric not null default 0,
  min_fee numeric not null default 0,
  currency text not null default 'ZAR',
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table commissions (
  id uuid primary key default gen_random_uuid(),
  percentage numeric(5,2) not null check (percentage between 0 and 100),
  effective_from timestamptz not null default now(),
  created_by uuid references users(id)
);

create table delivery_requests (
  id uuid primary key default gen_random_uuid(),
  partner_id uuid not null references partners(id),
  external_reference text not null,
  idempotency_key text not null,
  customer_name text,
  customer_phone text,
  pickup_address text not null,
  pickup geography(Point,4326) not null,
  destination_address text not null,
  destination geography(Point,4326) not null,
  vehicle_type vehicle_type not null,
  item_description text,
  weight_kg numeric, length_cm numeric, width_cm numeric, height_cm numeric,
  distance_km numeric,
  price numeric not null,
  currency text not null default 'ZAR',
  payment_method payment_method not null,
  created_at timestamptz not null default now(),
  unique (partner_id, idempotency_key),
  unique (partner_id, external_reference)
);

create table deliveries (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null unique references delivery_requests(id),
  driver_id uuid references driver_profiles(id),
  vehicle_id uuid references vehicles(id),
  status delivery_status not null default 'searching',
  delivery_otp_hash text,
  commission_percentage numeric(5,2),
  driver_earnings numeric,
  platform_commission numeric,
  assigned_at timestamptz, picked_up_at timestamptz, delivered_at timestamptz,
  cancelled_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index deliveries_driver_status_idx on deliveries (driver_id, status);
create trigger t_del_upd before update on deliveries for each row execute function set_updated_at();

create table delivery_offers (
  id uuid primary key default gen_random_uuid(),
  delivery_id uuid not null references deliveries(id) on delete cascade,
  driver_id uuid not null references driver_profiles(id),
  status offer_status not null default 'pending',
  expires_at timestamptz not null,
  created_at timestamptz not null default now(),
  unique (delivery_id, driver_id)
);

create table delivery_status_history (
  id bigserial primary key,
  delivery_id uuid not null references deliveries(id) on delete cascade,
  status delivery_status not null,
  changed_by uuid,
  note text,
  created_at timestamptz not null default now()
);

create or replace function accept_offer(p_offer_id uuid) returns boolean
language plpgsql security definer set search_path = public as $$
declare v_offer delivery_offers; v_rows int;
begin
  select * into v_offer from delivery_offers
   where id = p_offer_id and driver_id = auth.uid() and status = 'pending' and expires_at > now()
   for update;
  if not found then return false; end if;

  update deliveries set driver_id = v_offer.driver_id, status = 'driver_assigned', assigned_at = now()
   where id = v_offer.delivery_id and driver_id is null and status = 'searching';
  get diagnostics v_rows = row_count;
  if v_rows = 0 then return false; end if;

  update delivery_offers set status = 'accepted' where id = p_offer_id;
  update delivery_offers set status = 'expired'
   where delivery_id = v_offer.delivery_id and id <> p_offer_id and status = 'pending';
  insert into delivery_status_history (delivery_id, status, changed_by)
   values (v_offer.delivery_id, 'driver_assigned', auth.uid());
  return true;
end $$;
revoke execute on function accept_offer(uuid) from public, anon;
grant execute on function accept_offer(uuid) to authenticated;

alter table pricing_rules enable row level security;
alter table commissions enable row level security;
alter table delivery_requests enable row level security;
alter table deliveries enable row level security;
alter table delivery_offers enable row level security;
alter table delivery_status_history enable row level security;

create policy admin_all_pricing_rules on pricing_rules for all using (is_admin()) with check (is_admin());
create policy admin_all_commissions on commissions for all using (is_admin()) with check (is_admin());
create policy admin_all_delivery_requests on delivery_requests for all using (is_admin()) with check (is_admin());
create policy admin_all_deliveries on deliveries for all using (is_admin()) with check (is_admin());
create policy admin_all_delivery_offers on delivery_offers for all using (is_admin()) with check (is_admin());
create policy admin_all_delivery_status_history on delivery_status_history for all using (is_admin()) with check (is_admin());

create policy read_pricing on pricing_rules for select to authenticated using (true);

create policy driver_deliveries on deliveries for select using (
  driver_id = auth.uid()
  or exists (select 1 from delivery_offers o where o.delivery_id = deliveries.id and o.driver_id = auth.uid() and o.status = 'pending')
);
create policy driver_requests on delivery_requests for select using (
  exists (select 1 from deliveries d where d.request_id = delivery_requests.id and (d.driver_id = auth.uid()
    or exists (select 1 from delivery_offers o where o.delivery_id = d.id and o.driver_id = auth.uid() and o.status = 'pending')))
);
create policy driver_offers on delivery_offers for select using (driver_id = auth.uid());
create policy driver_history on delivery_status_history for select using (
  exists (select 1 from deliveries d where d.id = delivery_id and d.driver_id = auth.uid())
);
