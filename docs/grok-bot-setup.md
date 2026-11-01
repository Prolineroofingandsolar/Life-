# Grok Bot — setup

Grok Bot (x.ai/bot) works by using websites. Life is an iPhone app, so Life
gives Grok Bot a private web page instead. Grok Bot adds workouts, tasks and
so on there, and the app carries them out the next time it's open.

## How it works

1. In Life: **Settings → Grok Bot → Connect Grok Bot**. Copy the link.
2. In Grok Bot, paste the link and tell it what to do, for example:
   > This is my Life app. Every morning at 6am, open this link, look at my
   > recent workouts and the exercise library, and create a new workout for
   > today with "Create a new workout". Use exercise names exactly as listed.
3. Open Life. Whatever Grok Bot sent is done within a few seconds, and listed
   under Settings → Grok Bot. The page shows each request's status too.

What the page can do: create a workout (and plan it for today or tomorrow),
plan an existing routine, add or tick off a task, log a habit, water, a meal,
weight, or a supplement. It can't delete anything.

The link is the only key. Anyone with it can add things to Life. "Make a new
link" replaces it and "Switch off Grok Bot" stops it working straight away.

## Server

Two functions, in `functions/src/lifeBot.ts`:

- `lifeBot`: the web page (public URL, needs the secret link's key).
- `lifeBotApp`: what the app calls to make or switch off the link, and to
  collect requests.

Requests wait in Firestore under `users/{uid}/botInbox`. Link keys are stored
only as SHA-256 hashes, in `lifeBotTokens`. No new secrets, settings or
indexes are needed. Deploy as usual:

```
firebase deploy --only functions --project life-1812f
```

For agents that prefer JSON: `GET /lifeBot/api/state?key=…` returns the same
data as the page, and `POST /lifeBot/api/do?key=…` takes a JSON body with the
same fields as the forms (e.g. `{"kind":"createWorkout","name":"Legs",
"exercises":"Squat, 5x5, 3 min\nLeg Press, 3x10","when":"today"}`).
