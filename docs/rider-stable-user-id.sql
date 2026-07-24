-- Add a stable rider identity column.
-- Run this in Supabase SQL Editor.
--
-- After adding the column, set user_id for existing rider rows by matching
-- rider.email to auth.users.email. NIC can then be edited safely because the
-- app updates rows by user_id first.

alter table public.rider
  add column if not exists user_id uuid;

update public.rider r
set user_id = u.id
from auth.users u
where r.user_id is null
  and lower(r.email) = lower(u.email);

create unique index if not exists rider_user_id_unique
  on public.rider (user_id)
  where user_id is not null;

grant select, update on public.rider to authenticated;

drop policy if exists "Riders can read own rider row by user_id" on public.rider;
create policy "Riders can read own rider row by user_id"
  on public.rider for select
  using (auth.uid() = user_id);

drop policy if exists "Riders can update own rider row by user_id" on public.rider;
create policy "Riders can update own rider row by user_id"
  on public.rider for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
