-- Rider push notifications.
-- Run this in the Supabase SQL Editor AFTER deploying the notify-rider Edge
-- Function (see docs/push-notifications.md). Re-running it is safe.
--
--   admin assigns  ->  insert into trip (rider_nic = ...)
--                  ->  trigger  ->  pg_net  ->  notify-rider Edge Function
--                  ->  FCM      ->  rider's phone
--
-- Set the two settings in section 4 before the triggers can reach the function.

-- ---------------------------------------------------------------------------
-- 1. Where this phone can be reached.
-- ---------------------------------------------------------------------------

create table if not exists public.device_tokens (
  id uuid primary key default gen_random_uuid(),
  rider_id uuid not null references auth.users(id) on delete cascade,
  rider_nic text,
  token text not null unique,
  platform text not null default 'android',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists device_tokens_rider_id_idx
  on public.device_tokens (rider_id);
create index if not exists device_tokens_rider_nic_idx
  on public.device_tokens (rider_nic);

alter table public.device_tokens enable row level security;
grant select, insert, update, delete on public.device_tokens to authenticated;

drop policy if exists "Riders manage own device tokens" on public.device_tokens;
create policy "Riders manage own device tokens"
  on public.device_tokens for all
  using (auth.uid() = rider_id)
  with check (auth.uid() = rider_id);

-- ---------------------------------------------------------------------------
-- 2. In-app inbox. The Edge Function writes here; the rider only reads and
--    marks rows read, so there is no insert policy for authenticated.
-- ---------------------------------------------------------------------------

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  rider_id uuid references auth.users(id) on delete cascade,
  rider_nic text,
  type text not null default 'general',
  title text not null,
  body text not null default '',
  delivery_id text,
  trip_id text,
  data jsonb,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists notifications_rider_created_idx
  on public.notifications (rider_id, created_at desc);
create index if not exists notifications_unread_idx
  on public.notifications (rider_id)
  where read_at is null;

alter table public.notifications enable row level security;
grant select, update on public.notifications to authenticated;

drop policy if exists "Riders read own notifications" on public.notifications;
create policy "Riders read own notifications"
  on public.notifications for select
  using (auth.uid() = rider_id);

drop policy if exists "Riders mark own notifications read" on public.notifications;
create policy "Riders mark own notifications read"
  on public.notifications for update
  using (auth.uid() = rider_id)
  with check (auth.uid() = rider_id);

-- ---------------------------------------------------------------------------
-- 3. pg_net lets a trigger make an HTTP call without blocking the write.
-- ---------------------------------------------------------------------------

create extension if not exists pg_net with schema extensions;

-- ---------------------------------------------------------------------------
-- 4. Where the Edge Function lives, and the shared secret it checks.
--
--    REPLACE both values below, then run. Find the project ref in your
--    Supabase URL (https://<ref>.supabase.co). The secret is any random
--    string; set the SAME value on the function with:
--      supabase secrets set NOTIFY_WEBHOOK_SECRET=<the same string>
--
--    These are stored as database settings rather than inline in the trigger so
--    rotating the secret does not mean editing function bodies.
-- ---------------------------------------------------------------------------

do $$
begin
  execute format(
    'alter database %I set app.notify_function_url = %L',
    current_database(),
    'https://REPLACE_PROJECT_REF.supabase.co/functions/v1/notify-rider'
  );
  execute format(
    'alter database %I set app.notify_webhook_secret = %L',
    current_database(),
    'REPLACE_WITH_A_LONG_RANDOM_STRING'
  );
end
$$;

-- The settings above apply to NEW connections, so make them visible to this
-- session too, otherwise a trigger fired later in this same script sees null.
select set_config(
  'app.notify_function_url',
  'https://REPLACE_PROJECT_REF.supabase.co/functions/v1/notify-rider',
  false
);
select set_config(
  'app.notify_webhook_secret',
  'REPLACE_WITH_A_LONG_RANDOM_STRING',
  false
);

-- ---------------------------------------------------------------------------
-- 5. The trigger function. One function for every event; the Edge Function
--    decides what to send from the table name and the row.
-- ---------------------------------------------------------------------------

create or replace function public.notify_rider_event()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  function_url text := current_setting('app.notify_function_url', true);
  webhook_secret text := current_setting('app.notify_webhook_secret', true);
  payload jsonb;
begin
  -- Not configured yet: never block the admin's write because of it.
  if function_url is null or function_url = '' then
    raise notice 'app.notify_function_url is not set; skipping rider push';
    return coalesce(new, old);
  end if;

  payload := jsonb_build_object(
    'event', tg_argv[0],
    'table', tg_table_name,
    'op', tg_op,
    'record', case when new is null then null else to_jsonb(new) end,
    'old_record', case when old is null then null else to_jsonb(old) end
  );

  -- Fire and forget. pg_net queues the request, so a slow or failing function
  -- cannot roll back or delay the assignment itself.
  perform net.http_post(
    url := function_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-webhook-secret', coalesce(webhook_secret, '')
    ),
    body := payload,
    timeout_milliseconds := 5000
  );

  return coalesce(new, old);
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. The triggers.
-- ---------------------------------------------------------------------------

-- (a) New trip assigned to a rider.
drop trigger if exists trip_assigned_notify on public.trip;
create trigger trip_assigned_notify
  after insert on public.trip
  for each row
  when (new.rider_nic is not null)
  execute function public.notify_rider_event('trip_assigned');

-- (b) Existing trip handed to a different rider. Fires once for the new rider;
--     the Edge Function also notifies the previous one that it was taken away.
drop trigger if exists trip_reassigned_notify on public.trip;
create trigger trip_reassigned_notify
  after update of rider_nic on public.trip
  for each row
  when (new.rider_nic is distinct from old.rider_nic)
  execute function public.notify_rider_event('trip_reassigned');

-- (c) A delivery added to a trip the rider already has.
drop trigger if exists delivery_added_notify on public.delivery;
create trigger delivery_added_notify
  after insert on public.delivery
  for each row
  when (new.trip_id is not null)
  execute function public.notify_rider_event('delivery_added');

-- (d) A delivery cancelled, or moved to another trip.
drop trigger if exists delivery_changed_notify on public.delivery;
create trigger delivery_changed_notify
  after update on public.delivery
  for each row
  when (
    (new.delivery_status is distinct from old.delivery_status
      and lower(coalesce(new.delivery_status, '')) in
        ('cancelled', 'canceled', 'failed', 'returned', 'rejected'))
    or (new.trip_id is distinct from old.trip_id)
  )
  execute function public.notify_rider_event('delivery_changed');

-- ---------------------------------------------------------------------------
-- 7. Check it worked. Four triggers, two tables.
-- ---------------------------------------------------------------------------

select event_object_table, trigger_name, action_timing, event_manipulation
from information_schema.triggers
where trigger_name in (
  'trip_assigned_notify',
  'trip_reassigned_notify',
  'delivery_added_notify',
  'delivery_changed_notify'
)
order by event_object_table, trigger_name;

-- After assigning a test trip, the delivery attempt shows up here:
--   select * from net._http_response order by created desc limit 5;
