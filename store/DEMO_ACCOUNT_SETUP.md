# Store-reviewer demo account (myMinto Customer)

Apple (and Play closed review) reviewers must be able to log in. Because sign-in
is email-OTP, the app has a **built-in bypass** for one fixed demo account so a
reviewer never needs to receive an email.

## What the reviewer does (put this in the review notes)
1. Open the app → Login.
2. Email: the `REVIEWER_EMAIL` you set (suggested: `demo-customer@myminto.in`)
3. Tap **Send OTP**.
4. Enter code: the `REVIEWER_CODE` you set (e.g. `424242`)
5. Tap **Verify & Continue** → lands on the home screen with sample data.

## Credentials live in .env — NOT in the code
The reviewer email, code, and password are read from `.env` (gitignored) via
`REVIEWER_EMAIL`, `REVIEWER_CODE`, `REVIEWER_PASSWORD`. If any is blank the
bypass is disabled. **Choose a fresh password** — do not reuse the value that
was previously in git history.

Set them in `.env` before building the store submission, e.g.:
```
REVIEWER_EMAIL=demo-customer@myminto.in
REVIEWER_CODE=424242
REVIEWER_PASSWORD=<a fresh strong password>
```

## One-time setup you must do before submitting

### Step 1 — create the auth user (Supabase dashboard)
Authentication → **Users** → **Add user** → **Create new user**:
- Email: the same as `REVIEWER_EMAIL`
- Password: the same as `REVIEWER_PASSWORD` in `.env`
- ✅ tick **Auto Confirm User**

(The app signs this account in by password behind the bypass code — the password
must match `.env` exactly. To disable the bypass later, blank the .env values
and rebuild, or change the account password.)

### Step 2 — create its profile rows (SQL editor)
Run after Step 1:

```sql
-- Customer profile for the review demo account.
insert into public.users (id, email, phone, name, role, is_active)
select id, 'demo-customer@myminto.in', '+919999900000', 'Demo Customer', 'customer', true
from auth.users where email = 'demo-customer@myminto.in'
on conflict (id) do update set role = 'customer', is_active = true;

insert into public.customers (id, default_address, default_lat, default_lng)
select id, 'MG Road, Bengaluru, Karnataka', 12.9757, 77.6050
from auth.users where email = 'demo-customer@myminto.in'
on conflict (id) do nothing;
```

### Step 3 — give it something to see
Make sure at least one **verified, open shop with products** exists near the demo
address (lat 12.9757, lng 77.6050) so the reviewer sees shops and can place a
test Cash-on-Delivery order. Adjust the lat/lng above to wherever your pilot
shops are if not Bengaluru.

## Security note
The demo email + code + password are embedded in the app on purpose (that's how
reviewer accounts work). Worst case: someone signs into the demo customer and
places a COD order under it — no real user data is exposed. Change the password
in Step 1 after review to turn the bypass off.
