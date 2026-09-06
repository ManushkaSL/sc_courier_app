# Rider push notifications

When the admin assigns a rider, the rider's phone gets a notification — even
when the app is closed. Nothing in the admin tool changes: the trigger is the
database write itself.

```
Admin assigns rider
      |
      v
INSERT into public.trip (rider_nic = ...)
      |  Postgres trigger -> pg_net (async, never blocks the write)
      v
Edge Function  notify-rider
      |  NIC -> rider -> device_tokens
      |  also writes a row to public.notifications (the in-app inbox)
      v
FCM HTTP v1  ->  rider's phone
```

## What notifies the rider

| Event | Trigger | Message |
|---|---|---|
| New trip assigned | `insert on trip` | "New delivery assigned" |
| Trip moved to another rider | `update of rider_nic on trip` | new rider gets "New delivery assigned"; previous rider gets "Trip reassigned" |
| Delivery added to their trip | `insert on delivery` | "New delivery added" |
| Delivery cancelled | `update on delivery` to a cancelled status | "Delivery cancelled" |
| Delivery moved between trips | `update of trip_id on delivery` | both riders told |

Every one is also stored in `public.notifications`, so the rider can find it
later under the bell icon on the dashboard even if the push was swiped away,
denied, or arrived while the phone was off.

## Setup

Four steps. You need the Firebase console, the Supabase CLI, and the Supabase
SQL editor. The Android app is already registered in the Firebase project
`sccourier-ed01b` from before the Supabase migration, so no new Firebase app is
needed.

### 1. Firebase: get a service account key

1. [Firebase console](https://console.firebase.google.com/) → project
   **sccourier-ed01b** → gear icon → **Project settings**.
2. **Cloud Messaging** tab → confirm **Firebase Cloud Messaging API (V1)** is
   *Enabled*. (The old "Cloud Messaging API (Legacy)" is shut down and is not
   what this uses.)
3. **Service accounts** tab → **Generate new private key** → **Generate key**.
   A JSON file downloads. Treat it like a password: it can send notifications
   as your project.

### 2. Deploy the Edge Function

From the project root:

```bash
supabase login
supabase link --project-ref <your-project-ref>     # the <ref> in https://<ref>.supabase.co

# The shared secret the database uses to prove a request came from your triggers.
# Any long random string; you will paste the SAME value into the SQL in step 3.
supabase secrets set NOTIFY_WEBHOOK_SECRET='<long-random-string>'

# The whole service-account JSON from step 1, as one value.
supabase secrets set FIREBASE_SERVICE_ACCOUNT="$(cat /path/to/service-account.json)"

# --no-verify-jwt is required: the database calls this with the shared secret
# above, not with a Supabase user JWT.
supabase functions deploy notify-rider --no-verify-jwt
```

On Windows PowerShell, the service-account line is:

```powershell
supabase secrets set FIREBASE_SERVICE_ACCOUNT=(Get-Content .\service-account.json -Raw)
```

If the CLI complains that the project is not initialised, run `supabase init`
first and answer no to generating sample files.

### 3. Run the SQL

Open `docs/push-notifications.sql`, **replace the two placeholders**:

- `REPLACE_PROJECT_REF` → your project ref, in both places
- `REPLACE_WITH_A_LONG_RANDOM_STRING` → the exact `NOTIFY_WEBHOOK_SECRET` from
  step 2, in both places

Then paste the whole file into the Supabase SQL editor and run it. It creates
`device_tokens` and `notifications` with their RLS policies, enables `pg_net`,
and installs the four triggers. It ends by listing the triggers — you should
see four rows.

### 4. Rebuild the app

```bash
flutter pub get
flutter run
```

On first launch Android asks for notification permission. The app registers its
FCM token in `device_tokens` right after the dashboard loads, so **sign in at
least once on the phone before testing** — a rider with no token row gets an
inbox entry but no push.

## Testing

Assign a trip to a rider whose phone has signed in, then check in order:

```sql
-- 1. Did the trigger fire and reach the function? Look for status_code 200.
select id, status_code, content, created
from net._http_response
order by created desc
limit 5;

-- 2. Did the function record the notification?
select * from public.notifications order by created_at desc limit 5;

-- 3. Does the rider have a device registered at all?
select rider_id, rider_nic, platform, updated_at from public.device_tokens;
```

Function logs are under **Edge Functions → notify-rider → Logs** in the
dashboard, and show every FCM failure with its reason.

## Troubleshooting

**No row in `net._http_response`** — the trigger did not fire or `pg_net` is not
installed. Re-check that section 7 of the SQL listed four triggers.

**401 in `net._http_response`** — `NOTIFY_WEBHOOK_SECRET` and
`app.notify_webhook_secret` do not match. Re-run both, exactly.

**`No rider row for NIC ...` in the logs** — the trip's `rider_nic` matches no
`rider."NIC"`. This is the same NIC-based join the delivery list uses, so if the
rider can see their deliveries, this will resolve.

**`Rider ... has no registered devices`** — the rider has not signed in on a
phone since this feature shipped, or denied notification permission. The inbox
entry is still written.

**Inbox works, push does not** — almost always notification permission. Android
13+ only asks once; after a decline the rider must enable it under Settings →
Apps → SC Courier → Notifications.

**Tokens pile up** — a token that FCM reports as `UNREGISTERED` is deleted by
the function automatically. Nothing to maintain.

## Notes

- **Android only.** iOS needs a paid Apple Developer account, an APNs key
  uploaded to Firebase, and a `GoogleService-Info.plist`. The Dart and database
  sides are platform-agnostic; only `platform: 'android'` in `saveDeviceToken`
  and the manifest entries assume Android.
- **The app id is still `com.example.sc_courier`.** Google Play rejects
  `com.example.*`. Renaming it means re-registering the Android app in Firebase
  and replacing `android/app/google-services.json`, so do it before release.
- The service-account JSON is a Supabase secret and is never in the repo or the
  app. The app itself only ever holds its own FCM token.
