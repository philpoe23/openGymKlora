# Klora Fitness — Flutter client app (design)

Date: 2026-11-12 · Status: approved in brainstorming, building

## Goal

A native Flutter app for Klora Fitness **clients** (not the trainer) with the same look as the
web PWA (`frontend/`, `DESIGN.md`). Clients sign in to their trainer's instance, follow the
routines she assigns, log workouts in the gym, see progress, and check in with her. The web
PWA stays as is; both read and write the same per-user state, so a client can switch between them.

## Decisions

| Topic | Decision |
|---|---|
| Scope | Full client app: Home, Plan, Workout logger, Stats/History, Coach, Settings |
| Client role | Follow assigned routines + light edits (swap exercise, add/remove/skip sets). No building routines from scratch |
| Location | `app/` in this repo (package `klora_app`), Android + iOS |
| Engine | Port of `frontend/src/lib` training logic to pure Dart, with tests ported and JS↔Dart cross-check fixtures |
| Navigation | `glass_liquid_navbar` (`LiquidGlassNavbar`), `Scaffold.extendBody: true` |
| State mgmt | `provider` + one `ChangeNotifier` app store (mirrors the Zustand store) |

## Architecture

```
app/
  lib/
    engine/   pure Dart, no Flutter imports — ports of frontend/src/lib
    data/     state model (raw-JSON-preserving), API client, local cache, sync
    ui/       screens + widgets
    theme/    Klora tokens (DESIGN.md), light + dark
  test/       engine/, data/, ui/ tests
  tool/       node script that writes JS cross-check fixtures
```

### Engine (`lib/engine/`)
Ports of `progression`, `onerm`, `finish-workout`, `workout-model`, `supersetFlow`, and the
helpers they depend on (`history`, `format`, `plan-share`, state merge). Behaviour must match the
JS exactly. Each module has a `*_test.dart` with the JS test cases carried over, plus a
cross-check test that loads fixtures produced by running the JS lib (`tool/gen_fixtures.mjs`).

### Data (`lib/data/`)
- **State model** wraps the raw JSON map of the web `S` object; typed getters/setters only for
  fields the app uses. Unknown fields round-trip untouched.
- **API client** (`http`): base URL entered at sign-in, Bearer token in `flutter_secure_storage`.
- **Local cache**: `state.json` + `{rev, wid}` in the app documents dir (`path_provider`).
- **Sync**: on launch `GET /api/data` → `{state, rev}`. Each change: memory → disk → debounced
  `PUT /api/data {state, baseRev, baseWid}`. A 409 carries the server document; merge with the
  same rules as the web `pullState` and retry. Poll `GET /api/data/rev` on resume and every 30 s in
  the foreground. Failed pushes retry with backoff; a "Not synced" banner shows last-sync time.

### Auth
- Password: `POST /api/login/password {name, password, token: true}`. **API change**: when
  `token: true`, the response also includes `{ token }` (a `makeSession(user)` value, the same
  signed payload the cookie carries). Covered by a new api test.
- Pairing code: `POST /api/pair/redeem` (already returns a token).
- 401 → back to sign-in, local data kept. 403 `disabled` → show server message.

### UI
- Tabs (`LiquidGlassNavbar`, 4 items): **Home · Plan · Stats · Coach**. Glass tinted with blush /
  hot-rose via `LiquidGlassTheme`, following light/dark.
- **Start/Resume**: hot-rose floating pill above the navbar (the package has no centre button);
  shows elapsed time while a session runs; hidden on the workout screen.
- Screens: Sign-in (server URL, password or pairing code) · Home (today's routine, coach card,
  body-weight card, link to Settings) · Plan (assigned routines; swap exercise) · Workout ·
  Stats + History · Coach (assignments → "Add to my plan", check-in thread) · Settings (unit,
  theme, account, sign out).
- **Workout logger**: one exercise at a time (swipe) plus overview list; large weight/reps
  steppers, tap to type; tick logs the set, starts rest timer, vibrates. Rest timer with ±15 s and
  a local notification when backgrounded (`flutter_local_notifications`); screen kept awake
  (`wakelock_plus`). Light edits: swap exercise, add/remove set, skip. Finish runs
  `finish-workout` and shows a summary with PRs and "Send check-in to coach".
- Exercise media from the instance's `/api/media/…`, placeholder when missing.
- Charts (1RM trend, weekly volume) are drawn with `CustomPainter`.

### Theme
Tokens from `DESIGN.md`: hot-rose `#cf3a76` accent; blush surfaces (light) / plum surfaces
(dark); rack pastels (rose, lilac, mint, butter, peach, sky + inks) for load chips; Rubik bundled
as a font asset (from `frontend/src/fonts`).

## Out of scope for v1
AI coach chat, progress photos, measurements, structural balance / recovery maps, backup &
import, building routines from scratch, guest mode, passkeys, all trainer/admin screens.

## Dependencies
`glass_liquid_navbar`, `provider`, `http`, `flutter_secure_storage`, `path_provider`,
`flutter_local_notifications`, `wakelock_plus`. Rubik bundled. Nothing else.

## Testing / done
- `flutter analyze` clean, `flutter test` green (engine ports, cross-check fixtures, unknown-field
  round-trip, 409 merge+retry with a fake client, widget tests for stepper/tick/rest timer/nav).
- `cd api && npm test` green incl. the new `token: true` test.
- `flutter build apk --debug` succeeds.
