-- Push notification diagnostics.
-- Run the whole file in the Supabase SQL Editor after assigning a test trip,
-- then read the results tabs in order. Each query says what its answer means.

-- ===========================================================================
-- A. Did the trigger fire, and what did the Edge Function reply?
--    THIS IS THE ONE THAT MATTERS MOST.
--
--    no rows   -> the trigger never fired (or pg_net is not working)
--    404       -> the notify-rider function is not deployed
--    401       -> secret mismatch: the function's NOTIFY_WEBHOOK_SECRET does
--                 not equal notification_config.notify_webhook_secret
--    500       -> the function is deployed but its secrets are missing
--    200 + {"ok":true,"sent":0}  -> the function ran but decided there was
--                 nobody to notify (see C and D)
--    200 + {"ok":false,...}      -> the function threw; the error text is in
--                 the content column
-- ===========================================================================

select
  id,
  status_code,
  content,
  error_msg,
  created
from net._http_response
order by created desc
limit 10;

-- ===========================================================================
-- B. Is anything queued but never sent? Rows here that never appear in A mean
--    pg_net's background worker is stuck; restarting the project clears it.
-- ===========================================================================

select id, url, timed_out, created
from net.http_request_queue
order by created desc
limit 5;

-- ===========================================================================
-- C. Has any phone registered for push?
--    no rows -> no rider has signed in on a phone since the app was rebuilt
--               with notifications, so there is nowhere to send. This alone
--               explains "inbox works, no push".
-- ===========================================================================

select rider_id, rider_nic, platform, left(token, 18) || '...' as token, updated_at
from public.device_tokens
order by updated_at desc;

-- ===========================================================================
-- D. Did the function write an inbox row? If yes, the database half works
--    end to end and the problem is only the FCM half (check the function logs
--    under Edge Functions -> notify-rider -> Logs).
-- ===========================================================================

select id, rider_id, rider_nic, type, title, created_at
from public.notifications
order by created_at desc
limit 10;

-- ===========================================================================
-- E. Can the trip's rider_nic actually be matched to a rider row?
--    A null rider_id means the function cannot resolve who to notify: the
--    trip's rider_nic does not equal any rider."NIC".
-- ===========================================================================

select
  t.trip_id,
  t.rider_nic,
  coalesce(r.user_id, r.id) as rider_id,
  case when r.id is null then 'NO MATCHING RIDER ROW' else 'ok' end as status
from public.trip t
left join public.rider r on r."NIC" = t.rider_nic
order by t.trip_id desc
limit 10;

-- ===========================================================================
-- F. Confirm the config the trigger reads. The URL must be your project's, and
--    the secret must match what `supabase secrets list` shows for the function.
-- ===========================================================================

select key, value from public.notification_config order by key;

-- ===========================================================================
-- G. Send a test event without touching real data. Fires the same trigger the
--    admin would; re-run A afterwards to see the response.
--    REPLACE the NIC with a real rider's NIC first.
-- ===========================================================================

-- insert into public.trip (trip_id, rider_nic)
-- values ('TEST-' || floor(random() * 100000)::text, 'REPLACE_WITH_RIDER_NIC');
