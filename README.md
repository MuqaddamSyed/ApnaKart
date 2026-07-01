# QuickKart — Hyperlocal Quick Commerce (Tier 2/3 India)

A lightweight, cost-optimized quick-commerce platform inspired by Zepto/Blinkit, built as **one Flutter codebase with four app flavors**: Customer, Supplier, Delivery Agent, and Admin (web). Backend is Supabase (Postgres + Auth + Realtime + Storage). Maps use OpenStreetMap (no Google Maps). Phase 1 is Cash on Delivery only.

> **Status: scaffold / reference implementation.** This repo gives you a complete, modular project structure, a migration-ready Supabase schema with RLS + PostGIS, shared models/services, and working screens across all four apps. Wire it to a real Supabase project and build locally (see Setup). APKs and the deployed admin site are produced by running the build commands below; they are not pre-built here.

## Project structure

```
lib/
  apps/
    customer/   customer_main.dart   + screens/
    supplier/   supplier_main.dart   + screens/
    delivery/   delivery_main.dart   + screens/
    admin/      admin_main.dart (web) + screens/
  shared/
    models/     Dart models for every table
    services/   auth, order, product, location, notification
    widgets/    skeletons, product card, status stepper, offline banner
    utils/      formatters, distance, validators
  core/
    theme/      colors + Poppins theme
    constants/  app constants, Supabase keys
    routing/    go_router per flavor
supabase/
  01_schema.sql        tables + PostGIS function + triggers
  02_rls_policies.sql  row level security
  03_seed.sql          demo data
```

Each app is a separate entry point (`*_main.dart`); all share `lib/shared` and `lib/core`.

## Platform folders (Android + Web) — pre-wired

The `android/` and `web/` folders are already generated and configured, so you do **not** need to run `flutter create` for them. What's set up:

- `android/app/build.gradle` — applicationId `com.quickkart.app`, **minSdk 21**, targetSdk 34, multidex, Firebase BoM + `firebase-messaging`, Google Services plugin.
- `android/app/src/main/AndroidManifest.xml` — permissions: `INTERNET`, `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`, `CALL_PHONE`, `POST_NOTIFICATIONS`, `WAKE_LOCK`; `tel:` intent query for tap-to-call; FCM default channel; vector launcher icon (brand colour, no PNG assets needed).
- `android/settings.gradle`, `build.gradle`, `gradle.properties`, wrapper properties, `MainActivity.kt`, launch theme + night theme.
- `web/index.html` + `manifest.json` for the admin dashboard.

**Two generated bits Flutter must add on first run** (machine-specific / binary — can't be committed by hand):

1. `android/local.properties` — auto-created by Flutter, points to your local Flutter SDK + Android SDK.
2. `android/gradle/wrapper/gradle-wrapper.jar` + `gradlew` scripts — binary wrapper.

To fill just those without touching the pre-wired files, run once in the project root:

```bash
flutter create . --platforms=android,web --org com.quickkart
```

`flutter create` only **adds missing** generated files; it leaves the existing gradle/manifest/source files intact.

**Required before an Android build succeeds:** drop your real `android/app/google-services.json` from Firebase (package name `com.quickkart.app`). See `android/app/google-services.json.PLACEHOLDER`. To build temporarily without Firebase, comment out the two `com.google.gms.google-services` plugin lines and the `firebase-messaging` dependency (instructions in the placeholder file).

## Setup

### 1. Supabase
1. Create a project at supabase.com, copy the Project URL and anon key.
2. SQL editor: run in order `supabase/01_schema.sql`, `supabase/02_rls_policies.sql`, `supabase/04_otp_and_earnings.sql`, `supabase/05_email_auth.sql`, `supabase/06_partner_approval.sql`, `supabase/07_push_notifications.sql`, then optionally `supabase/03_seed.sql`. `01` enables `postgis` + `nearby_suppliers()`; `04` enables `pgcrypto` and adds the hashed-OTP + atomic-earnings RPCs; `05` enables email OTP login while keeping one mandatory unique phone number per account and logging phone-reuse attempts; `06` gates suppliers and delivery agents behind admin approval; `07` stores FCM tokens for push notifications.
3. Auth > Providers > Email: enable email OTP/magic-link login. Supabase's default email sender is enough for a small pilot.
4. Database Realtime: enable for `orders` and `delivery_agents`.
5. Storage: create a public bucket named `product-images`.

### 1b. Edge Functions (delivery OTP)
The delivery OTP is verified server-side. Deploy the function (needs the Supabase CLI, `supabase link`ed to your project):
```bash
cd supabase
supabase functions deploy verify-delivery-otp
```
Details + optional daily earnings-reset cron in `supabase/functions/README.md`.

### 2. Firebase (push)
1. Because the three flavors have **different applicationIds**, register all three package names in your Firebase project (`com.quickkart.customer`, `com.quickkart.supplier`, `com.quickkart.delivery`). Then either:
   - download a single `google-services.json` that contains all three and place it at `android/app/google-services.json`, **or**
   - place a per-flavor file at `android/app/src/<flavor>/google-services.json`.
2. Put your FCM server key in `.env`.

### 3. Env & deps
```bash
cp .env.example .env   # fill SUPABASE_URL, SUPABASE_ANON_KEY, FCM_SERVER_KEY
flutter pub get
```
`.env` is loaded at startup via flutter_dotenv and bundled as an asset.

## Run & build (flavors)
Each Android app is a **product flavor** (`customer`, `supplier`, `delivery`) with its own
applicationId, name, and icon — they install side-by-side. Pass `--flavor` with the
matching entry point. Admin is web (no flavor).

```bash
# Run
flutter run --flavor customer -t lib/apps/customer/customer_main.dart
flutter run --flavor supplier -t lib/apps/supplier/supplier_main.dart
flutter run --flavor delivery -t lib/apps/delivery/delivery_main.dart
flutter run -d chrome           -t lib/apps/admin/admin_main.dart

# Android debug APKs
flutter build apk --debug --flavor customer -t lib/apps/customer/customer_main.dart
flutter build apk --debug --flavor supplier -t lib/apps/supplier/supplier_main.dart
flutter build apk --debug --flavor delivery -t lib/apps/delivery/delivery_main.dart

# Admin web (deploy build/web to Vercel/Netlify)
flutter build web -t lib/apps/admin/admin_main.dart
```

| Flavor   | applicationId             | App name            | Icon  |
|----------|---------------------------|---------------------|-------|
| customer | com.quickkart.customer    | QuickKart           | orange|
| supplier | com.quickkart.supplier    | QuickKart Partner   | green |
| delivery | com.quickkart.delivery    | QuickKart Delivery  | blue  |
Output APKs are flavor-specific, e.g. `build/app/outputs/flutter-apk/app-customer-debug.apk`. Target Android API 21+. Product flavors are already configured in `android/app/build.gradle`.

## Business logic baked in
- Supplier discovery: PostGIS `ST_DWithin` within 5 km via `nearby_suppliers()`; only open + verified.
- Discount: `round((mrp-sale_price)/mrp*100)`; badge when >= 5%.
- Delivery fee: flat Rs.20; free when total > Rs.500.
- Delivery OTP: 4-digit generated on placement; stored server-side as a **bcrypt hash** only (plaintext kept locally on the customer device). Agent submits it to the `verify-delivery-otp` Edge Function, which verifies the hash and **atomically** marks delivered + credits agent earnings.
- Lifecycle: placed -> confirmed -> preparing -> picked_up -> on_the_way -> delivered (cancel only while `placed`).
- Realtime: supplier new-order feed, customer status + agent location, admin live feed; agent location every 10s on delivery.

## Phase 2 (structured for, not built)
UPI (Razorpay/Cashfree), agent wallet, ratings/reviews, referrals, Google Maps upgrade, iOS, Kannada/Hindi i18n, medical verification, scheduled slots.

## Design system
Primary `#FF4500`, secondary `#2ECC71`, bg `#F8F8F8`, Poppins, 12px card / 8px button radius, 48px touch targets, skeleton loading, offline banner, cached images, animations <= 300ms.
