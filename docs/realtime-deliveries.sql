-- Live delivery updates on the rider dashboard.
--
-- Supabase only streams changes for tables that are in the supabase_realtime
-- publication. Without this, the app subscribes successfully and then never
-- hears anything, which looks exactly like the feature not working.
--
-- Run this in the Supabase SQL Editor. Re-running it is safe.

-- ---------------------------------------------------------------------------
-- 1. Stream changes for the tables the dashboard watches.
-- ---------------------------------------------------------------------------

do $$
begin
  begin
    alter publication supabase_realtime add table public.trip;
  exception
    when duplicate_object then
      raise notice 'public.trip is already published';
  end;

  begin
    alter publication supabase_realtime add table public.delivery;
  exception
    when duplicate_object then
      raise notice 'public.delivery is already published';
  end;

  begin
    alter publication supabase_realtime add table public.notifications;
  exception
    when duplicate_object then
      raise notice 'public.notifications is already published';
  end;
end
$$;

-- ---------------------------------------------------------------------------
-- 2. Deletes and filters need the old row, which Postgres only sends when the
--    table replicates full rows. Without this an admin deleting an assignment
--    reaches the app as an empty payload.
-- ---------------------------------------------------------------------------

alter table public.trip replica identity full;
alter table public.delivery replica identity full;

-- ---------------------------------------------------------------------------
-- 3. IMPORTANT, read this.
--
--    Realtime respects row level security. If RLS is OFF on trip/delivery,
--    every signed-in rider receives every other rider's rows as they change.
--    The app ignores the payload and re-fetches through the normal authorized
--    query, so the list stays correct either way -- but the broadcast itself
--    would be leaking data.
--
--    Check where you stand:
-- ---------------------------------------------------------------------------

select
  relname as table_name,
  case when relrowsecurity then 'RLS on' else 'RLS OFF - see below' end as status
from pg_class
where relname in ('trip', 'delivery', 'notifications')
  and relnamespace = 'public'::regnamespace;

-- If either says "RLS OFF", turn it on with policies matching how the app
-- reads: a rider sees a trip whose rider_nic is their own NIC, and a delivery
-- belonging to one of those trips. Uncomment and run:
--
-- alter table public.trip enable row level security;
-- grant select on public.trip to authenticated;
--
-- drop policy if exists "Riders read own trips" on public.trip;
-- create policy "Riders read own trips"
--   on public.trip for select
--   using (
--     rider_nic in (
--       select r."NIC" from public.rider r
--       where r.id = auth.uid() or r.user_id = auth.uid()
--     )
--   );
--
-- alter table public.delivery enable row level security;
-- grant select, update on public.delivery to authenticated;
--
-- drop policy if exists "Riders read own deliveries" on public.delivery;
-- create policy "Riders read own deliveries"
--   on public.delivery for select
--   using (
--     trip_id in (
--       select t.trip_id from public.trip t
--       where t.rider_nic in (
--         select r."NIC" from public.rider r
--         where r.id = auth.uid() or r.user_id = auth.uid()
--       )
--     )
--   );
--
-- drop policy if exists "Riders update own deliveries" on public.delivery;
-- create policy "Riders update own deliveries"
--   on public.delivery for update
--   using (
--     trip_id in (
--       select t.trip_id from public.trip t
--       where t.rider_nic in (
--         select r."NIC" from public.rider r
--         where r.id = auth.uid() or r.user_id = auth.uid()
--       )
--     )
--   )
--   with check (true);
--
-- TEST SIGNING IN AS A RIDER AFTER ENABLING THIS. If the policies do not match
-- how your rows are keyed, the delivery list goes empty rather than wrong, and
-- you can drop the policies again.

-- ---------------------------------------------------------------------------
-- 4. Confirm what is being streamed.
-- ---------------------------------------------------------------------------

select schemaname, tablename
from pg_publication_tables
where pubname = 'supabase_realtime'
order by tablename;
