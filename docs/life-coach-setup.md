# Life Coach — setup

What to do to make the coach actually talk to Gemini. Until these steps are
done the coach works from local rules, which is a supported state rather than a
broken one — the card appears, the suggestions are real, and nothing is sent
anywhere.

Run everything from the repository root.

---

## 1. Before you start

- Firebase project: `life-1812f`
- **Blaze plan** must be enabled. Cloud Functions won't deploy on Spark.
- Node 20 and the Firebase CLI:
  ```
  npm install -g firebase-tools
  firebase login
  ```

---

## 2. Get a Gemini API key — the paid tier

Create the key in [Google AI Studio](https://aistudio.google.com/apikey), on a
Cloud project **with billing enabled**.

This is not about cost. Google's free tier may use submitted content to improve
their products; the paid tier does not. Since the coach sends your sleep and
recovery figures, the paid tier is the point, and the spend at one user is
pennies a month regardless.

Note the model identifier from Google's current docs while you're there — a
Flash-Lite model for this workload. It goes in the config below rather than in
code, because model names change often enough that hardcoding one guarantees a
future outage.

---

## 3. Store the key as a secret

```
cd functions
firebase functions:secrets:set GEMINI_API_KEY --project life-1812f
```

Paste the key when prompted. It goes into Secret Manager and is injected at
runtime. It is never in the repository, never in the app bundle, and never in
an env file.

To confirm it exists without printing it:

```
firebase functions:secrets:access GEMINI_API_KEY --project life-1812f
```

---

## 4. Configure the rest

```
cp functions/.env.example functions/.env.life-1812f
```

Then edit it and set at minimum:

```
GEMINI_MODEL=<the identifier from step 2>
```

The remaining values have working defaults — hourly request limit, monthly cost
ceiling, and the per-million-token prices used to estimate spend against that
ceiling. Check the prices against Google's current rates for the model you
chose; they only affect the estimate, not the bill.

`.gitignore` already excludes `functions/.env.*` while keeping the example.

---

## 5. Deploy

```
cd functions
npm install
npm run build          # typecheck first — deploy failures are slower to read
firebase deploy --only functions --project life-1812f
```

The output names both deployed functions and their URLs:

```
Function URL (coach(europe-west2)): https://europe-west2-life-1812f.cloudfunctions.net/coach
```

---

## 6. Point the app at it

The app defaults to `https://europe-west2-life-1812f.cloudfunctions.net`, which
is what step 5 produces for this project and region. If your URL differs — a
different region, or a second-generation runtime with a `run.app` address — set
it in the app under **Settings ▸ Coach ▸ Backend**, using the base URL *without*
the function name on the end.

Getting this wrong produces a coach that silently falls back to local rules,
which looks like the feature working rather than failing. If the card always
says "Life's own rules" after you've enabled AI, check this first.

---

## 7. Turn it on

In the app: **Settings ▸ Coach ▸ Use AI**, read the consent screen, accept.

Nothing is sent before that. The consent flag and the AI switch are separate,
and both must be on.

---

## Checking it works

The card's last line names its source. "AI coach" means the round trip
succeeded. "Life's own rules" means it didn't, and the line under it says why.

Usage and spend appear under **Settings ▸ Coach ▸ Usage**, refreshed from each
response.

---

## If it doesn't

| Symptom | Cause |
|---|---|
| Always "Life's own rules" | Wrong backend URL, or AI not enabled, or not signed in |
| "Sign in to use the coach" | Firebase Auth session expired — sign out and back in |
| "The coach is unavailable (401)" | `GEMINI_API_KEY` missing or wrong |
| "The coach is unavailable (404)" | `GEMINI_MODEL` isn't a model your key can reach |
| "Too many coach requests" | Hourly limit hit; raise `COACH_HOURLY_CALLS` if you mean to |
| "This month's AI limit has been reached" | Cost ceiling hit; raise `COACH_MONTHLY_COST_CEILING` |

Function logs — which deliberately contain no prompt content and no health
data, only statuses:

```
firebase functions:log --only coach --project life-1812f
```

---

## Turning it off

- **In the app:** Settings ▸ Coach ▸ Use AI. The coach keeps working locally.
- **Everywhere at once:** set `COACH_ENABLED=false` and redeploy. Every call
  then fails fast without touching Gemini, and every client falls back.
- **Completely:** `firebase functions:delete coach coachUsage --project life-1812f`

---

## What is sent

Listed in full on the consent screen, and defined in `CoachContext.swift` —
which is the authority, since what that struct holds is exactly what leaves the
device.

Summarised: derived figures only. Sleep duration and quality against your own
baseline, recovery as words rather than raw numbers, steps and active minutes
with their goals, whether a workout is planned, counts of outstanding tasks and
habits, and a note of anything missing or partial.

Never sent: your name, email, account details, raw Apple Health or Fitbit
records, provider tokens, location, photos, or notes. Task and habit *names* are
off by default and have their own switch — a task title routinely names a real
person.
