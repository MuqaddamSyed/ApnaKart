# myMinto — Store data-disclosure cheat sheet

Fill Google Play **Data safety** and Apple **App Privacy** using the rows below.
This reflects the **Customer** app. (Supplier/Delivery apps collect the same
account + location data and can reuse this.)

**Golden rule for both stores:** what you declare here must match what the app
actually does and what the Privacy Policy says. Mismatches are a top rejection
reason.

---

## Data the app collects

| Data type | Collected? | Linked to user? | Used for tracking?* | Purpose |
|---|---|---|---|---|
| Name | Yes | Yes | No | App functionality, account |
| Email address | Yes | Yes | No | Account / OTP sign-in |
| Phone number | Yes | Yes | No | Account, order coordination |
| Precise location (GPS) | Yes | Yes | No | App functionality (delivery) — **while in use only** |
| Coarse location | Yes | Yes | No | Show nearby shops |
| Physical/delivery address | Yes | Yes | No | Delivery |
| Purchase/order history | Yes | Yes | No | App functionality |
| Device identifiers (push token) | Yes | Yes | No | Order notifications |

*“Tracking” = sharing with data brokers or for cross-app advertising. **You do none of this**, so answer **No** everywhere.

**NOT collected:** payment/financial info (Cash on Delivery — no card data), health, contacts, photos, browsing history, audio.

---

## Google Play — Data safety form answers

- **Does your app collect or share user data?** → **Yes**
- For each row above: **Collected = Yes**, **Shared = Yes** only for the items
  passed to shops/agents/service providers (name, phone, address, location);
  choose **Shared** for those, **Collected-only** for the rest.
- **Is all data encrypted in transit?** → **Yes** (HTTPS/TLS)
- **Do you provide a way to request data deletion?** → **Yes**, in-app
  (**Profile → Delete account**) — also give your Privacy Policy URL.
- **Location → is it used in the background?** → **No** (in-use only). This
  matters: answering Yes triggers extra review.
- **Data used for tracking / advertising?** → **No**

### Android permissions to justify (Play will ask)
- `ACCESS_FINE_LOCATION` / `ACCESS_COARSE_LOCATION` — "Deliver orders to the
  customer's location and show nearby shops. Used only while the app is in use."
- `INTERNET`, `POST_NOTIFICATIONS` — standard app + order notifications.
- **No** `ACCESS_BACKGROUND_LOCATION` is requested (good — avoids the
  background-location declaration form).

---

## Apple — App Privacy ("nutrition label") answers

Add these **Data Types** (Contact Info, Location, User Content, Identifiers):

| Apple data type | Purpose | Linked | Tracking |
|---|---|---|---|
| Name | App Functionality | Yes | No |
| Email Address | App Functionality | Yes | No |
| Phone Number | App Functionality | Yes | No |
| Precise Location | App Functionality | Yes | No |
| Coarse Location | App Functionality | Yes | No |
| Physical Address | App Functionality | Yes | No |
| Purchase History | App Functionality | Yes | No |
| Device ID | App Functionality | Yes | No |

- **Used to track you?** → No, for all.
- **iOS Info.plist purpose string** (required, or the app is rejected):
  `NSLocationWhenInUseUsageDescription` =
  *"myMinto uses your location to show nearby shops and deliver your orders to the right place."*
  (Do **not** add `NSLocationAlwaysUsageDescription` — we never use background location.)

---

## Account deletion (both stores now require this)

- **In-app path:** Profile → Delete account (two-step confirm).
- **Public URL:** the Privacy Policy (section 5) documents the steps — use the
  Privacy Policy URL as the required "account deletion" URL if asked.
- **What happens:** personal data + sign-in identity deleted; past orders
  anonymised for shop records.

---

## Payments note (avoids the IAP trap)

All goods are **physical**, paid **Cash on Delivery**. Physical goods are exempt
from Apple/Google in-app-purchase rules — **do not** add StoreKit/Play Billing,
and make sure there are no digital-goods purchases anywhere in the app.
