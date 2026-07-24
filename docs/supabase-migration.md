# Firebase to Supabase migration

## 1. Create Supabase project

Create a Supabase project, then copy:

- Project URL
- publishable key

Run the app with:

```sh
flutter run --dart-define=SUPABASE_URL=YOUR_URL --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
```

This app defaults to:

- `SUPABASE_URL=https://lzoxjmevvjycclfwjtks.supabase.co`
- `SUPABASE_PUBLISHABLE_KEY=sb_publishable_mQt-t-8nWjJ7Bya_EVdkaA_QhZr80qu`
- `SUPABASE_RIDER_TABLE=rider`

For production builds, pass `--dart-define` values only if you need to override these defaults.

## 2. Create database tables and policies

Open Supabase Dashboard > SQL Editor and run:

```sql
-- paste docs/supabase-migration.sql here
```

This creates:

- `rider`
- `deliveries`
- `rider_locations`
- public `rider-assets` storage bucket
- RLS policies so riders can access only their own rows/assets

## 3. Move users

Firebase Auth passwords cannot be exported in a way that can be directly imported by the Supabase client app.

Practical options:

- Ask riders to reset/create their password in Supabase.
- Use a temporary admin migration script with Supabase service-role credentials to create users, then send password reset links.
- Keep Firebase Auth temporarily while gradually moving profiles/data, then cut over auth later.

The app now expects Supabase Auth user IDs as `rider.id`.

## 4. Move Firestore data

Export current Firestore `riders`, `deliveries`, and `riderLocations` data, transform it to rows, and import into Supabase. Keep the old Firebase UID in `firebase_uid` if you need historical lookup, but set `rider.id` and `deliveries.rider_id` to the matching Supabase Auth user UUID.

## 5. Move Storage files

Upload existing Firebase Storage rider/NIC images into the `rider-assets` bucket:

- `rider_profiles/{supabase_user_id}/{file}`
- `NIC_images/{supabase_user_id}/{file}`

Then update the URL fields in `rider`.

## 6. Remove Firebase project files later

After the app is tested against Supabase, you can remove Firebase deployment files such as `firebase.json`, `firestore.rules`, `firestore.indexes.json`, `storage.rules`, and platform `google-services.json` files if no other app still uses them.
