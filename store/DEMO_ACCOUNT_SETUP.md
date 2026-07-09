# Store-reviewer demo account (myMinto Customer)

Apple (and Play closed review) reviewers must be able to log in. Because sign-in
is email-OTP, the app has a **built-in bypass** for one fixed demo account so a
reviewer never needs to receive an email.

## What the reviewer does (put this in the review notes)
1. Open the app → Login.
2. Email: **demo-customer@myminto.in**
3. Tap **Send OTP**.
4. Enter code: **424242**
5. Tap **Verify & Continue** → lands on the home screen with sample data.

(These values are already in `store/listing_customer.md` reviewer notes.)

## One-time setup you must do before submitting

### Step 1 — create the auth user (Supabase dashboard)
Authentication → **Users** → **Add user** → **Create new user**:
- Email: `demo-customer@myminto.in`
- Password: `REDACTED-ROTATED`
- ✅ tick **Auto Confirm User**

(The app signs this account in by password behind the bypass code — the password
must match exactly. To disable the bypass later, just change this password.)

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
