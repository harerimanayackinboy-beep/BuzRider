create extension if not exists "postgis";

create type vehicle_type as enum ('motorcycle','car','van','truck');

create table vehicles (
  id uuid primary key default gen_random_uuid(),
  driver_id uuid not null references driver_profiles(id) on delete cascade,
  type vehicle_type not null,
  registration_number text not null unique,
  capacity_kg numeric,
  max_load_kg numeric,
  length_cm numeric,
  width_cm numeric,
  height_cm numeric,
  photo_paths text[] default '{}',
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table driver_documents (
  id uuid primary key default gen_random_uuid(),
  driver_id uuid not null references driver_profiles(id) on delete cascade,
  document_type text not null check (document_type in
    ('id','passport','driving_licence','vehicle_registration','proof_of_address','profile_photo')),
  file_path text not null,
  verification_status verification_status not null default 'pending',
  reviewed_by uuid references users(id),
  rejection_reason text,
  uploaded_at timestamptz not null default now()
);

create table driver_locations (
  driver_id uuid primary key references driver_profiles(id) on delete cascade,
  location geography(Point,4326) not null,
  updated_at timestamptz not null default now()
);
create index driver_locations_gix on driver_locations using gist (location);

alter table vehicles enable row level security;
alter table driver_documents enable row level security;
alter table driver_locations enable row level security;

create policy admin_all_vehicles on vehicles for all using (is_admin()) with check (is_admin());
create policy admin_all_driver_documents on driver_documents for all using (is_admin()) with check (is_admin());
create policy admin_all_driver_locations on driver_locations for all using (is_admin()) with check (is_admin());

create policy own_vehicles on vehicles for all
  using (driver_id = auth.uid()) with check (driver_id = auth.uid());

create policy own_docs_select on driver_documents for select using (driver_id = auth.uid());
create policy own_docs_insert on driver_documents for insert
  with check (driver_id = auth.uid() and verification_status = 'pending');

create policy own_location on driver_locations for all
  using (driver_id = auth.uid()) with check (driver_id = auth.uid());

insert into storage.buckets (id, name, public)
values ('driver-documents', 'driver-documents', false)
on conflict (id) do nothing;

create policy docs_upload_own on storage.objects for insert to authenticated
  with check (bucket_id = 'driver-documents' and (storage.foldername(name))[1] = auth.uid()::text);
create policy docs_read_own on storage.objects for select to authenticated
  using (bucket_id = 'driver-documents' and (storage.foldername(name))[1] = auth.uid()::text);
create policy docs_admin_read on storage.objects for select to authenticated
  using (bucket_id = 'driver-documents' and is_admin());
