-- SC Courier Supabase schema.
-- Run this in Supabase SQL Editor before using the migrated Flutter app.

create extension if not exists pgcrypto;

create table if not exists public.rider (
  id uuid primary key references auth.users(id) on delete cascade,
  user_id uuid,
  firebase_uid text,
  full_name text,
  "Name" text,
  email text,
  "Email" text,
  phone_number text,
  "Phone_Number" text,
  branch text,
  "Branch" text,
  nic_number text,
  "NIC" text,
  home_address text,
  "Address" text,
  emergency_contact text,
  "Emergency_Contact" text,
  vehicle_type text,
  "Vehicle_Type" text,
  vehicle_number text,
  "Vehicle_No" text,
  driving_license text,
  "Driver_Licence_No" text,
  nic_front_image text,
  "NIC_Front_Image" text,
  nic_back_image text,
  "NIC_Back_Image" text,
  profile_photo_url text,
  "Profile_Photo_Url" text,
  live_location jsonb,
  is_tracking boolean default false,
  last_location_at timestamptz,
  profile_completed_at timestamptz,
  created_at timestamptz default now(),
  created_at_iso text,
  updated_at timestamptz default now()
);

create table if not exists public.deliveries (
  id uuid primary key default gen_random_uuid(),
  tracking_code text,
  parcel_id text,
  rider_id uuid references public.rider(id) on delete set null,
  pickup_address text,
  delivery_address text,
  distance double precision,
  price numeric(12, 2),
  package_description text,
  recipient_name text,
  recipient_phone text,
  status text not null default 'pending',
  live_tracking_enabled boolean default true,
  rider_live_location jsonb,
  rider_location_updated_at timestamptz,
  created_at timestamptz default now(),
  created_at_iso text,
  updated_at timestamptz
);

create table if not exists public.rider_locations (
  id uuid primary key references public.rider(id) on delete cascade,
  rider_id uuid references public.rider(id) on delete cascade,
  latitude double precision,
  longitude double precision,
  accuracy double precision,
  speed double precision,
  heading double precision,
  is_online boolean default false,
  updated_at timestamptz default now(),
  stopped_at timestamptz
);

create index if not exists deliveries_rider_status_idx
  on public.deliveries (rider_id, status);

create index if not exists deliveries_created_at_idx
  on public.deliveries (created_at desc);

alter table public.rider enable row level security;
alter table public.deliveries enable row level security;
alter table public.rider_locations enable row level security;

grant usage on schema public to anon, authenticated;
grant select, insert, update on public.rider to authenticated;
grant select, insert, update on public.deliveries to authenticated;
grant select, insert, update on public.rider_locations to authenticated;

drop policy if exists "Riders can read own profile" on public.rider;
create policy "Riders can read own profile"
  on public.rider for select
  using (auth.uid() = id);

drop policy if exists "Riders can insert own profile" on public.rider;
create policy "Riders can insert own profile"
  on public.rider for insert
  with check (auth.uid() = id);

drop policy if exists "Riders can update own profile" on public.rider;
create policy "Riders can update own profile"
  on public.rider for update
  using (auth.uid() = id)
  with check (auth.uid() = id);

drop policy if exists "Riders can read own deliveries" on public.deliveries;
create policy "Riders can read own deliveries"
  on public.deliveries for select
  using (auth.uid() = rider_id);

drop policy if exists "Riders can create own deliveries" on public.deliveries;
create policy "Riders can create own deliveries"
  on public.deliveries for insert
  with check (auth.uid() = rider_id);

drop policy if exists "Riders can update own deliveries" on public.deliveries;
create policy "Riders can update own deliveries"
  on public.deliveries for update
  using (auth.uid() = rider_id)
  with check (auth.uid() = rider_id);

drop policy if exists "Riders can read own location" on public.rider_locations;
create policy "Riders can read own location"
  on public.rider_locations for select
  using (auth.uid() = id);

drop policy if exists "Riders can upsert own location" on public.rider_locations;
create policy "Riders can upsert own location"
  on public.rider_locations for insert
  with check (auth.uid() = id);

drop policy if exists "Riders can update own location" on public.rider_locations;
create policy "Riders can update own location"
  on public.rider_locations for update
  using (auth.uid() = id)
  with check (auth.uid() = id);

insert into storage.buckets (id, name, public)
values ('rider-assets', 'rider-assets', true)
on conflict (id) do update set public = excluded.public;

drop policy if exists "Riders can read rider assets" on storage.objects;
create policy "Riders can read rider assets"
  on storage.objects for select
  using (bucket_id = 'rider-assets');

drop policy if exists "Riders can upload own rider assets" on storage.objects;
create policy "Riders can upload own rider assets"
  on storage.objects for insert
  with check (
    bucket_id = 'rider-assets'
    and auth.uid()::text = (storage.foldername(name))[2]
  );

drop policy if exists "Riders can update own rider assets" on storage.objects;
create policy "Riders can update own rider assets"
  on storage.objects for update
  using (
    bucket_id = 'rider-assets'
    and auth.uid()::text = (storage.foldername(name))[2]
  )
  with check (
    bucket_id = 'rider-assets'
    and auth.uid()::text = (storage.foldername(name))[2]
  );
