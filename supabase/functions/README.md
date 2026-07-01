# QuickKart Edge Functions

Deno/TypeScript functions deployed to Supabase. They close two production
hardening gaps: hashed-OTP delivery verification and atomic agent earnings.

## Prerequisites
- Supabase CLI installed and logged in: `supabase login`
- Project linked: `supabase link --project-ref YOUR_REF`
- SQL migrations applied, including `../04_otp_and_earnings.sql`
  (creates pgcrypto, `otp_hash`, `set_order_otp`, `confirm_delivery_atomic`).

## Deploy
```bash
# from the supabase/ folder
supabase functions deploy verify-delivery-otp
supabase functions deploy send-push
```
`SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` are
injected automatically — you do NOT set them manually.

## How it's called from the app
The delivery app invokes it with the agent's session:
```dart
final res = await supabase.functions.invoke(
  'verify-delivery-otp',
  body: {'orderId': orderId, 'otp': enteredOtp},
);
final ok = (res.data as Map)['success'] == true;
```

## Optional: daily earnings reset
`reset_daily_earnings()` (in 04_otp_and_earnings.sql) zeroes
`earnings_today`. Schedule it at local midnight with pg_cron:
```sql
select cron.schedule('reset-earnings', '30 18 * * *',  -- 00:00 IST = 18:30 UTC
  $$ select reset_daily_earnings(); $$);
```
(Enable the `pg_cron` extension first.)

## Push notifications
`send-push` sends Firebase Cloud Messaging notifications to saved
`device_tokens`. Create a Firebase service account key, then set these secrets:

```bash
supabase secrets set FIREBASE_PROJECT_ID=your-project-id
supabase secrets set FIREBASE_CLIENT_EMAIL=your-service-account-email
supabase secrets set FIREBASE_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n"
supabase functions deploy send-push
```
