# KinOrbit (Flutter + Supabase MVP)

KinOrbit is a privacy-first family location sharing app. This branch now includes name-only anonymous authentication, circle-based sharing, live foreground sharing, and optional background sharing controls.

The public product name is **KinOrbit**. Existing identifiers such as
`com.safecircle.gps`, the Supabase project name, and Firebase project ID remain
unchanged to preserve compatibility with the already configured infrastructure
and Google Play release.

## Demo-ready setup

- App runs in **real Supabase/Firebase mode by default**.
- Demo mode is available only when `SAFE_CIRCLE_DEMO_MODE=true`.
- If `.env` is missing required keys and demo mode is off, app shows a clear configuration error on startup.
- Demo mode still uses an in-memory backend for review when explicitly enabled.

## Required Flutter version

- Verified with Flutter **3.44.7** and Dart SDK compatible with
  `>=3.4.0 <4.0.0` (`pubspec.yaml`).

## Tech stack

- Flutter (latest stable)
- Riverpod for state management
- Supabase for anonymous Auth + Postgres + Realtime
- Google Maps for map rendering
- geolocator + battery_plus for location capture and battery metadata

Firebase Cloud Messaging is wired end-to-end:

- App registers FCM token after user grants notification permission.
- SOS, safe zone, and sharing-paused alerts are sent through Supabase Edge Function fan-out.
- Recipients are filtered by circle membership and per-user notification preferences.

## Project structure

- `lib/core/` shared constants, theme and reusable widgets
- `lib/features/` feature-first UI/state
  - `auth/` name-only onboarding and persistent device session
  - `map/` map screen + permission gate + realtime markers
  - `circles/` family circles, member list, invite code flow
  - `safe_zones/` create/edit/delete zones, assignments, geofence UI
  - `history/` your own history
  - `settings/` sharing controls + privacy settings
- `lib/models/` typed domain models
- `lib/repositories/` Supabase boundary layer
- `lib/services/` platform and infrastructure services

## Setup

1. Install dependencies:

```bash
flutter pub get
```

2. Copy and edit environment variables:

```bash
cp .env.example .env
```

3. Configure backend credentials in `.env` or use `--dart-define`.

This repository is currently linked to the dedicated Supabase project `SafeCircle GPS`:

- `SUPABASE_URL=https://bwiihydbnoroaiqpglco.supabase.co`
- `SUPABASE_ANON_KEY` is prefilled in `/Users/home/Documents/GPS_Track_Mobile_APP/.env`

Example `.env` values:

```env
SUPABASE_URL=https://bwiihydbnoroaiqpglco.supabase.co
SUPABASE_ANON_KEY=sb_publishable_your-key
GOOGLE_MAPS_ANDROID_API_KEY=android_maps_key
GOOGLE_MAPS_IOS_API_KEY=ios_maps_key
APPLE_PREMIUM_SUBSCRIPTION_IDS=com.example.safecircle.premium.month
GOOGLE_PREMIUM_SUBSCRIPTION_IDS=premium_month
SAFE_CIRCLE_DEMO_MODE=false
```

### Name-only onboarding

Enter a display name and tap **Continue**. No email, password, or social
provider is shown. In live mode, Supabase creates a unique anonymous user and
persists its session on the device. In demo mode, the same UI uses the in-memory
review backend.

Anonymous users cannot recover the same account after signing out, clearing app
data, or moving to another device. The Settings screen therefore displays a
clear warning before removing the local account.

4. (Optional) run with explicit defines:

```bash
flutter run -d android \
  --dart-define=SUPABASE_URL=your_supabase_url \
  --dart-define=SUPABASE_ANON_KEY=your_supabase_anon_key

flutter run -d ios \
  --dart-define=SUPABASE_URL=your_supabase_url \
  --dart-define=SUPABASE_ANON_KEY=your_supabase_anon_key
```

5. Run on emulator/simulator:

```bash
flutter run -d android
flutter run -d ios
```

6. Apply Supabase migrations in order:

```bash
supabase db push
```

The SafeCircle migrations and RLS policies are applied to project
`bwiihydbnoroaiqpglco`.

### Supabase anonymous authentication

- Anonymous sign-ins are enabled for project `bwiihydbnoroaiqpglco`.
- The client stores only the chosen display name in user metadata.
- Every account still receives a unique `auth.uid()` and uses the existing RLS
  circle-membership policies.
- Location sharing remains disabled until accepted circle membership and an
  explicit **Start sharing** action.
- Production rollout should add CAPTCHA/Turnstile abuse protection before
  opening public registration at scale.

### Google Maps setup

- Billing account is linked to Google Cloud project `safecircle-gps`.
- `Maps SDK for Android` and `Maps SDK for iOS` are enabled.
- `SafeCircle Maps Android` is restricted to:
  - API: Maps SDK for Android
  - package: `com.safecircle.gps`
  - debug SHA-1: `67:4C:04:00:8A:C8:3C:AF:D4:6D:AC:13:D1:54:46:76:52:B3:A1:7B`
- `SafeCircle Maps iOS` is restricted to:
  - API: Maps SDK for iOS
  - bundle ID: `com.safecircle.gps`
- Real key values remain only in ignored local files `.env` and
  `ios/Flutter/Secrets.xcconfig`.

### Push notifications and SOS setup

Firebase project `safecircle-gps` is registered for both platforms:

- Android package: `com.safecircle.gps`
- iOS bundle ID: `com.safecircle.gps`
- Android config: `android/app/google-services.json`
- iOS config: `ios/Runner/GoogleService-Info.plist`

Android applies the Google Services Gradle plugin. iOS includes Push Notifications,
Remote notifications background mode, and the Firebase plist in the Runner target.

1. For Google Maps, place restricted platform keys in local configuration:
   - `.env`: `GOOGLE_MAPS_ANDROID_API_KEY=...`
   - `.env`: `GOOGLE_MAPS_IOS_API_KEY=...`
   - `ios/Flutter/Secrets.xcconfig`: `GOOGLE_MAPS_IOS_API_KEY=...`
   - Android reads its key from `.env` during Gradle configuration.
   - iOS reads its key from the ignored `Secrets.xcconfig` file.
2. Set Edge Function secrets:
   - `SUPABASE_URL`
   - `SUPABASE_SERVICE_ROLE_KEY`
   - `FIREBASE_SERVICE_ACCOUNT` (complete Firebase service-account JSON)
3. Deploy the notification function:

```bash
supabase functions deploy safe-circle-notify
```

4. In-app flow:
   - open **Settings** → **Push notifications** to enable/disable alerts.
   - open **Map** and tap **SOS** to send SOS + location.
   - safe-zone enter/exit and sharing pause events send optional alerts automatically.

### Notification behavior

- SOS:
  - Creates row in `sos_events` with current position + telemetry.
  - Push payload includes latitude/longitude and actor context.
- Safe-zone events:
  - Event is recorded in `safe_zone_events`.
  - Enter/exit alert is delivered to accepted circle members when enabled.
- Sharing paused:
  - Pause action sends a family alert with current position.

### Location history

- Open **History** from main navigation.
- Select a circle member and one of:
  - Today
  - Yesterday
  - Last 24 hours
- The map renders the selected member’s route for the selected window and a timestamped list of points.
- History visibility is gated by circle membership and the same row-level policy used for live locations, so members can only view data for accepted circles.

### Retention and cleanup

- `history_retention_hours` defaults to 24 (free).
- 7-day and 30-day options are exposed in Settings for premium-tier planning.
- `supabase/migrations/20260725_safe_circle_history_retention_cleanup.sql` introduces:
  - schema support for retention preference
  - SQL cleanup function `public.delete_expired_location_updates()`
- Suggested production cleanup with `pg_cron`:
  - `select cron.schedule('safe_circle_cleanup_locations', '0 * * * *', 'select public.delete_expired_location_updates();');`
- Run on a schedule approved by your compliance/security review.

## Safe zones (geofencing)

- Open **Zones** from the bottom navigation.
- Create a zone by entering:
  - name
  - center latitude and longitude
  - radius (meters)
  - assignment (all members or one selected member)
- Zones render as circles on the map.
- Enter/exit transitions are detected during active sharing and persisted to `safe_zone_events` with fields:
  - `zone_id`
  - `user_id`
  - `event_type`
  - `event_timestamp`
- Detection throttling in the app prevents repeated notifications:
  - transition debounce window and cooldown in the sharing stream,
  - only transitions after stable state change are recorded.
- Push notifications are prepared by trigger `public.notify_safe_zone_event()` in migration
  `20260726_safe_circle_safe_zones.sql` (wire this to worker/webhook/Fn as needed).

## Permissions and background behavior

### iOS

- Add to `ios/Runner/Info.plist`:
  - `NSLocationWhenInUseUsageDescription`
  - `NSLocationAlwaysAndWhenInUseUsageDescription`
  - `NSLocationAlwaysUsageDescription`
  - `UIBackgroundModes` with `location`
- Users are first presented with a custom explanation screen before any OS permission prompt.
- Background sharing is off by default and can only be enabled from Settings via explicit confirmation.

### Android

- Add to `android/app/src/main/AndroidManifest.xml`:
  - `ACCESS_COARSE_LOCATION`
  - `ACCESS_FINE_LOCATION`
  - `ACCESS_BACKGROUND_LOCATION`
  - `FOREGROUND_SERVICE`
  - `FOREGROUND_SERVICE_LOCATION`
  - `POST_NOTIFICATIONS` (Android 13+)
- Foreground permission is requested before background flow.
- Background mode uses a visible foreground service notification while active.

### User control

- Share is manual: no tracking until **Start sharing** is tapped.
- Controls:
  - **Start sharing**
  - **Pause sharing**
  - **Stop sharing**
- Settings:
  - Background sharing on/off
  - Update interval (seconds)
  - Distance filter (meters)
  - Battery saving mode
- UI always shows status text: `Location sharing is active`, `Location sharing paused`, or `Location sharing is stopped`.

## Freemium subscriptions

- Subscription data model is implemented in `subscription_plans` and `user_subscriptions`:
  - Free: 1 circle, 2 members per circle, 24h history.
  - Premium: more circles/members + safe zones + SOS + priority location updates.
- Feature access is guarded in app screens and DB checks for write protection.

### Paywall configuration

- Product IDs are loaded from build-time environment variables (not hardcoded):
  - `APPLE_PREMIUM_SUBSCRIPTION_IDS`
  - `GOOGLE_PREMIUM_SUBSCRIPTION_IDS`

- Example run command:

```bash
flutter run \
  --dart-define=SUPABASE_URL=... \
  --dart-define=SUPABASE_ANON_KEY=... \
  --dart-define=APPLE_PREMIUM_SUBSCRIPTION_IDS="com.yourteam.safecircle.premium.month,com.yourteam.safecircle.premium.year" \
  --dart-define=GOOGLE_PREMIUM_SUBSCRIPTION_IDS="premium_month,premium_year"
```

### Store setup notes (App Store / Google Play)

- Apple App Store:
  - Create one subscription group with monthly/annual tiers that map to your product IDs.
  - Keep product identifiers in the App Store Connect dashboard only; never embed real IDs in source.
  - Enable Sandbox and StoreKit testing:
    - Add internal test accounts.
    - Test upgrade, downgrade, cancel, and restore flows.
  - For production, use the same `APPLE_PREMIUM_SUBSCRIPTION_IDS` values injected at build time.
- Google Play:
  - Create managed subscriptions in Play Console with the matching IDs from `GOOGLE_PREMIUM_SUBSCRIPTION_IDS`.
  - Add internal test users and validate subscription state transitions.
  - Verify restore and billing update behavior from the app flow.
  - Use the same IDs in release builds via build defines.
- Entitlement sync (both stores):
  - Treat `in_app_purchase` callbacks as signals only.
  - Update `public.user_subscriptions` in a trusted backend path (Edge Function / webhook handler).
  - Set `status` to `active`/`trialing`/`expired`/etc. and keep `platform_customer_id`, `platform_purchase_id`, or `metadata` for audit.
  - App-side checks always read `subscriptionStateProvider`, so entitlement updates must arrive from server-side verification.

## Supabase migration files

- `supabase/migrations/20260720_safe_circle_init.sql`
- `supabase/migrations/20260721_safe_circle_circle_invites_rls.sql`
- `supabase/migrations/20260722_safe_circle_location_updates_extensions.sql`
- `supabase/migrations/20260723_safe_circle_location_sharing_rls_realtime.sql`
- `supabase/migrations/20260724_safe_circle_background_and_location_updates.sql`
- `supabase/migrations/20260725_safe_circle_history_retention_cleanup.sql`
- `supabase/migrations/20260726_safe_circle_safe_zones.sql`
- `supabase/migrations/20260727_safe_circle_notifications.sql`
- `supabase/migrations/20260728_safe_circle_subscriptions_rls.sql`

## Privacy-first / store-ready notes

- Explain-before-permission: app only asks for location and explicitly describes foreground vs background usage.
- Explicit user action gating: no auto-tracking in background/foreground.
- Full state visibility: sharing status and active/paused indicators are always shown.
- Background tracking always requires explicit background permission and can be turned off from Settings any time.
- Realtime updates are scoped by circle membership.
- Database defaults prevent stealth behavior by keeping sharing disabled until user interaction.
- Push alerts are opt-in, and each user can disable each alert type from settings.

For app store/compliance wording, keep permission rationale screens aligned with:
- clear family-safety purpose
- why background is needed
- that users can disable background at any time
- what data is stored (timestamp, lat/long, accuracy, speed, heading, battery)
- that no tracking continues after stop/disable
