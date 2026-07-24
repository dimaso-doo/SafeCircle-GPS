# SafeCircle GPS Demo Checklist

## 1) Name-only onboarding test
- Open app in clean state.
- Enter a display name and tap Continue.
- Verify user lands in map/circles flow.
- Verify no email, password, or social login is requested.
- Restart the app and verify the anonymous Supabase session persists.
- Open Settings and verify account removal shows the recovery warning.

## 2) Create circle test
- Open Family/Circles screen.
- Tap Create Circle.
- Verify circle is created and appears in the list.
- Save invite code.

## 3) Join circle test
- Open circle join screen.
- Enter a valid invite code.
- Verify user is added as member.
- Verify app shows accepted-membership dependent state for sharing.

## 4) Map screen test
- Go to Map screen.
- Grant/confirm foreground location (demo mode can auto-provide sample positions).
- Verify sharing status text:
  - "Location sharing is stopped"
  - "Location sharing is active"
  - "Location sharing is paused"
- Tap Start sharing and watch markers move.
- Verify Safe Zone markers appear on map (if created).

## 5) Location permission test
- Revoke location permissions from OS settings.
- Return to app and verify permission gate appears.
- Re-enable permission and continue.
- Confirm app does not auto-track until Start sharing is tapped.
