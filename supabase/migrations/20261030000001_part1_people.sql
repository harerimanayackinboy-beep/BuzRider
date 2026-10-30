create extension if not exists "pgcrypto";

create type verification_status as enum ('pending','approved','rejected','suspended');

create or replace function set_updated_at() returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end $$;

create table users (
  id uuid primary key references auth.users(id) on delete cascade,
  role text not null default 'driver' check (role in ('driver','admin')),
  full_name text,
  phone text,
  email text,
  language text not null default 'en' check (language in ('en','zu','xh','fr','rn')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table admin_users (
  user_id uuid primary key references users(id) on delete cascade,
  admin_role text not null default 'support' check (admin_role in ('super_admin','finance','support','verifier')),
  created_at timestamptz not null default now()
);

create or replace function is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from admin_users where user_id = auth.uid());
$$;

create table partners (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  api_key_hash text not null unique,
  webhook_url text,
  webhook_secret text,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table driver_profiles (
  id uuid primary key references users(id) on delete cascade,
  profile_photo_url text,
  verification_status verification_status not null default 'pending',
  is_online boolean not null default false,
  rating_avg numeric(3,2) not null default 0,
  rating_count int not null default 0,
  bank_details jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint online_requires_approval check (not is_online or verification_status = 'approved')
);

create or replace function handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.users (id, email, phone) values (new.id, new.email, new.phone);
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function handle_new_user();

create trigger t_users_upd before update on users for each row execute function set_updated_at();
create trigger t_dp_upd before update on driver_profiles for each row execute function set_updated_at();

alter table users enable row level security;
alter table admin_users enable row level security;
alter table partners enable row level security;
alter table driver_profiles enable row level security;

create policy admin_all_users on users for all using (is_admin()) with check (is_admin());
create policy admin_all_admin_users on admin_users for all using (is_admin()) with check (is_admin());
create policy admin_all_partners on partners for all using (is_admin()) with check (is_admin());
create policy admin_all_driver_profiles on driver_profiles for all using (is_admin()) with check (is_admin());

create policy own_user on users for select using (id = auth.uid());
create policy own_user_upd on users for update using (id = auth.uid())
  with check (id = auth.uid() and role = 'driver');

create policy own_profile on driver_profiles for select using (id = auth.uid());
create policy own_profile_ins on driver_profiles for insert
  with check (id = auth.uid() and verification_status = 'pending' and not is_online);
create policy own_profile_upd on driver_profiles for update
  using (id = auth.uid()) with check (id = auth.uid());

revoke update on driver_profiles from authenticated;
grant update (is_online, profile_photo_url, bank_details) on driver_profiles to authenticated;
