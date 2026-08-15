# Life

A calm, native iPhone app built for ADHD brains — one place for your day, tasks,
training, health, habits, body care and money.

## Features

- **Today** — the day at a glance: a swipeable health carousel, body-care rings
  (hydrate / nourish / move), and a coach card with the one thing worth doing
  next.
- **Tasks** — quick capture, due dates and reminders, a calendar and stats.
- **Train** — a full gym logger with an active-workout mode, rest timer and Live
  Activity, plus an automation layer that plans progression, spots plateaus,
  schedules deloads, suggests substitutions and reschedules missed sessions.
- **Health** — Apple Health and Google/Fitbit as sources, with a per-metric
  preference for which to trust. Sleep scoring, heart-rate zones, HRV, recovery
  and readiness, all refreshed in the background.
- **Coach** — a daily recommendation, morning and evening briefings, and an Ask
  screen. Backed by Gemini when enabled, and by Life's own rules when not.
- **More** — habits with streaks and a heatmap, body composition and progress
  photos, direct debits, calculators and achievements.
- **Widgets** — tasks, habits (tappable to complete), and the coach tip, plus a
  Live Activity for the workout you're in the middle of.
- Sign in with Apple, cross-device sync, and light & dark themes.

## Tech

Native **SwiftUI**, iOS 17.6+, with WidgetKit, ActivityKit, HealthKit and
BGTaskScheduler. **Firebase Auth** (Sign in with Apple) and **Firestore** for
sync. The AI coach runs through **Firebase Cloud Functions** (TypeScript) as a
proxy to **Gemini** — the API key lives in Secret Manager and never reaches the
app.

```
Life/                 the app
LifeTasksWidget/      widget extension and Live Activity
LifeTests/            ~500 tests (Swift Testing)
LifeUITests/          UI tests
functions/            the Gemini proxy, its validators and tests
firestore.rules       database security rules
docs/                 Life Coach design, setup and known limitations
```

## Develop

Open `Life.xcodeproj` in Xcode. The project uses file-system-synchronized
groups, so a file dropped into a target's folder is part of that target — there
is no membership to maintain.

```bash
./scripts/build-and-test.sh     # build + run the suite on a simulator
```

The full, untruncated `xcodebuild` output lands in `build-log.txt`. Overrides:
`SCHEME=LifeTasksWidgetExtension` to build the widget alone, `SKIP_TESTS=1` to
build only.

For the backend:

```bash
cd functions
npm install
npm run typecheck
npm test          # validator tests + security rules against the emulator
```

## The coach

Off by default, and useful without ever being turned on — with AI disabled it
runs on local rules, and nothing leaves the device. Enabling it needs a Gemini
key and a deploy; see [`docs/life-coach-setup.md`](docs/life-coach-setup.md).
What it does *not* do is written down just as plainly in
[`docs/life-coach-limitations.md`](docs/life-coach-limitations.md).

## A note on `src/`

There is a React/Vite PWA in `src/`, with `index.html`, `capacitor.config.ts`,
the Tailwind and Vite configs and a Cloudflare `wrangler.jsonc`. **It is an
earlier prototype, superseded by the native app, and it is not part of it.**
There is no Capacitor bridge and no `ios/` directory; the Swift app never loads
a web view. The prototype stores everything in `localStorage` with no accounts
and no sync, and it does not have Health, Train, Coach or widgets.

It is kept for reference. Don't build on it, and don't take `npm run deploy` at
the repository root for a way to ship this app.
