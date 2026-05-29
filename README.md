# Life

A calm, Apple-style productivity PWA built for ADHD brains — one place for your day, tasks, workouts, habits, body care, and money.

## Features

- **Today** — daily dashboard with Apple-Activity-style body-care rings (hydrate / nourish / move) and a hyperfocus timer that nudges you to take breaks.
- **Tasks** — quick-capture to-dos across Work / Gym / Personal with swipe-to-delete.
- **Train** — a full gym logger: routines & templates, an active-workout mode with an auto rest timer, PRs, streaks, and a training calendar.
- **Habits** — build good habits and break bad ones: daily / weekday / weekly schedules, quantified targets, streaks, a heatmap calendar, and "days clean" tracking.
- **Body** — water / meal / break reminders and daily goals.
- **Money** — monthly direct debits with due-date countdowns.
- Light & dark themes (follows the system, with a manual toggle), installable to your iPhone Home Screen.

## Tech

Vite · React · TypeScript · Tailwind CSS · Framer Motion · Lucide icons · `vite-plugin-pwa`. All data is stored locally in the browser (`localStorage`) — no backend, no accounts.

## Develop

```bash
npm install
npm run dev      # local dev server
npm run build    # production build → dist/
npm run preview  # preview the production build
```

## Deploy

Hosted on **Cloudflare Pages**:

- **Build command:** `npm run build`
- **Build output directory:** `dist`
