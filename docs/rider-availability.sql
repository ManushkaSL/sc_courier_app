-- Rider availability.
-- Run this in the Supabase SQL Editor (Dashboard -> SQL Editor -> New query),
-- paste the whole file, then press Run. Re-running it is safe.
--
-- Riders set their own work state from the dashboard header. The admin side
-- should only offer new deliveries to riders sitting on 'available'.
--
--   available   -> ready to receive new deliveries
--   on_delivery -> working on a delivery right now
--   offline     -> not working, do not assign
--
-- The app reads and writes public.rider.availability_status.

-- ---------------------------------------------------------------------------
-- 1. Columns. availability_status already exists on most projects; this only
--    fills in what is missing. availability_updated_at is optional -- the app
--    drops it from the write if the table does not have it.
-- ---------------------------------------------------------------------------

alter table public.rider
  add column if not exists availability_status text;

alter table public.rider
  add column if not exists availability_updated_at timestamptz;

-- ---------------------------------------------------------------------------
-- 2. Normalise whatever is already in the column onto the three keys the app
--    uses, so the constraint below cannot fail on legacy rows. Rows with no
--    value become 'offline', which keeps them out of assignment until the
--    rider picks a state in the app.
-- ---------------------------------------------------------------------------

update public.rider
set availability_status = case
  when availability_status is null then 'offline'
  when lower(trim(availability_status)) in ('available', 'online', 'active', 'ready')
    then 'available'
  when lower(trim(availability_status)) in ('on_delivery', 'on delivery', 'on_ride', 'on ride', 'busy', 'delivering')
    then 'on_delivery'
  else 'offline'
end
where availability_status is null
   or availability_status not in ('available', 'on_delivery', 'offline');

alter table public.rider
  alter column availability_status set default 'offline';

alter table public.rider
  alter column availability_status set not null;

-- ---------------------------------------------------------------------------
-- 3. Guard the allowed values. Dropped first so re-running stays safe.
-- ---------------------------------------------------------------------------

alter table public.rider
  drop constraint if exists rider_availability_status_check;

alter table public.rider
  add constraint rider_availability_status_check
  check (availability_status in ('available', 'on_delivery', 'offline'));

create index if not exists rider_availability_status_idx
  on public.rider (availability_status);

-- ---------------------------------------------------------------------------
-- 4. Check it worked: both columns listed, and every row on a known value.
-- ---------------------------------------------------------------------------

select column_name, data_type, column_default, is_nullable
from information_schema.columns
where table_schema = 'public'
  and table_name = 'rider'
  and column_name in ('availability_status', 'availability_updated_at');

select availability_status, count(*)
from public.rider
group by availability_status
order by availability_status;

-- ---------------------------------------------------------------------------
-- 5. Optional: a view for the admin tool listing riders that can take work.
--
-- Only id/user_id/availability columns are selected because those are certain
-- to exist; the rider table has drifted over time and naming a missing column
-- would abort this whole script (the SQL editor runs it as one transaction, so
-- the changes above would roll back with it). Join back to public.rider for
-- names and phone numbers.
--
-- Wrapped in a block so that if anything here fails the columns above still
-- commit. security_invoker needs Postgres 15+; on an older project the view is
-- dropped again rather than left readable by every signed-in rider.
-- ---------------------------------------------------------------------------

do $$
begin
  execute '
    create or replace view public.available_riders as
      select id, user_id, availability_status, availability_updated_at
      from public.rider
      where availability_status = ''available''';

  begin
    -- Run the view as the caller so rider RLS still applies to it. The admin
    -- tool uses the service role, which bypasses RLS and still sees everyone.
    execute 'alter view public.available_riders set (security_invoker = on)';
    execute 'grant select on public.available_riders to authenticated';
  exception
    when others then
      execute 'drop view if exists public.available_riders';
      raise notice
        'available_riders skipped: this Postgres cannot enforce security_invoker (%).',
        sqlerrm;
  end;
exception
  when others then
    raise notice 'Optional available_riders view skipped: %', sqlerrm;
end
$$;

-- The existing "Riders can update own profile" / "...own rider row by user_id"
-- policies already cover writing this column, so no new policy is needed.
