# Life Coach — architecture findings and implementation plan

Steps 1–3 of the brief: what's already here, what gets built, and the decisions
that were taken rather than assumed.

Nothing in this document has been implemented. It exists to be argued with
before code is written.

---

## 1. What the app already does

The deterministic-cleaning layer the brief asks for is largely built. This is
the single most important finding, because it changes the size of the feature:
`CoachContext` is a **builder over existing types**, not a new computation
engine.

| Brief's requirement | Already provided by |
|---|---|
| Deduplicate overlapping Fitbit / Apple Health records | `GoogleHealthService.reduceToDailyTotals` — identity-keyed, whole-day snapshots collapsed rather than summed |
| Apply the user's preferred source per metric | `HealthSync.source(for:)` — explicit choice honoured, falls back only when the chosen device is absent |
| Trusted daily totals | `HealthDay`, `CareDay`, merged field-by-field so a short sync never blanks a longer one |
| Baseline comparisons | `AppState.healthBaseline(_:days:minimumSamples:)`, `HealthInsights.trend` |
| Detect missing / partial data | Every `HealthDay` metric is `Optional`; nil means *not recorded* and is deliberately never zero. `HealthInsights.WeekToDate` tracks coverage days |
| Readiness / sleep / activity scores | `HealthInsights.readinessScore`, `.sleepScore`, `.activityScore` — each refuses to produce a number from too little history |
| Training load | `AppState.completedWorkouts`, `WorkoutSession.totalVolumeKg`, `plannedSessions` |
| Task urgency | `AppTask.resolvedDate`, `.priority`, `.reminderDate` |
| Habit progress | `Habit.logs`, `AppState.streakFor` |
| Provider naming | `HealthProvider` — one mapping, one spelling per provider |

**Consequence:** the coach must read these, never recompute them. A second
implementation of "what were my steps today" that disagreed with the Health tab
would be worse than no coach at all.

### Patterns to follow

- **State** — `AppState` is `@Observable`; everything persists through
  `StateSnapshot` (`Codable`) to `UserDefaults`, and to Firestore as one JSON
  blob via `FirestoreSync`.
- **Adding stored state** — new fields on `StateSnapshot` and `HealthSettings`
  must be `Optional` or decoded with `decodeIfPresent`. Swift's synthesised
  decoder *throws* on a missing non-optional key, and `AppState.load()` treats a
  decode failure as first launch — so a carelessly added field wipes every
  existing save. `HealthSettings` already has a hand-written `init(from:)` for
  exactly this reason; follow it.
- **Mutation** — `appState.setHealthSettings { $0.x = y }`; every mutator ends
  in `save()`.
- **Settings UI** — self-contained sections, e.g. `GoogleHealthSettingsSection`.
- **Tests** — Swift Testing (`import Testing`, `struct FooTests`), not XCTest.
- **Secrets** — `GoogleHealthConfig` keeps the OAuth *client ID* (public by
  design) in `UserDefaults` and the *tokens* in the Keychain. No secret has ever
  been committed. That holds.

### What does not exist

- **Any backend.** `wrangler.jsonc` has no `main` — it is assets-only, left from
  the abandoned React web app under `src/`. There is no Firebase Functions
  setup. The proxy is built from nothing.
- Any AI, network client beyond `GoogleHealthService`, or chat UI.

---

## 2. Decisions taken

| Decision | Choice | Why |
|---|---|---|
| Backend host | **Firebase Cloud Functions** (callable) | The app already uses Firebase Auth. A callable function receives the verified caller identity, so an unauthenticated proxy — a Gemini key anyone can spend — is impossible by construction rather than by remembering to check. Requires the Blaze plan. |
| Gemini model | **Env var, no default in the app** | Model identifiers change and I will not assert one from memory. `GEMINI_MODEL` is set at deploy time from Google's current docs. |
| Search grounding | **Off** | Per brief. |
| Where cleaning happens | **On device, before the call** | Per brief, and because the trusted numbers already live there. |
| Failure behaviour | **Deterministic local suggestion** | The coach degrades to a rule-based recommendation rather than an error card. This also satisfies "disable cloud AI entirely" with no second code path. |

---

## 3. Files, by stage

Each stage is independently buildable. Build after each; errors stay small and
attributable.

### Stage 1 — Backend and context

```
functions/                          NEW — Firebase Functions (TypeScript)
  src/index.ts                        callable `coach`, auth-gated
  src/gemini.ts                       the only place the API key is read
  src/schema.ts                       response schema + server-side validation
  src/limits.ts                       per-user rate and monthly cost ceiling
  .env.example                        GEMINI_API_KEY, GEMINI_MODEL, limits
Life/Coach/CoachContext.swift       NEW — the payload, Codable, no identifiers
Life/Coach/CoachContextBuilder.swift NEW — reads AppState/HealthInsights only
Life/Coach/CoachModels.swift        NEW — response, actionType enum, evidence
LifeTests/CoachContextTests.swift   NEW — missing data, partial days, source
                                          selection, hashing
.gitignore                          EDIT — functions/.env, .runtimeconfig.json
```

`CoachContext` carries no name, email, raw samples or tokens — only derived
figures, each with a `confidence` and a source label. `dataWarnings` names what
was missing so the model can hedge instead of inventing.

### Stage 2 — Service, caching, cost, consent

```
Life/Coach/CoachService.swift       NEW — calls the function, validates, retries
                                          once with a repair request, then falls
                                          back locally
Life/Coach/CoachCache.swift         NEW — context-hash keyed; briefing and review
                                          cached per day
Life/Coach/CoachUsage.swift         NEW — tokens and estimated cost per call,
                                          monthly ceiling
Life/Coach/LocalCoach.swift         NEW — deterministic fallback; also the whole
                                          feature when cloud AI is off
Life/Models.swift                   EDIT — `CoachSettings` (decodeIfPresent)
Life/AppState.swift                 EDIT — `coachSettings` on StateSnapshot
LifeTests/CoachServiceTests.swift   NEW — mocked responses only, never live
```

### Stage 3 — UI

```
Life/Coach/CoachCard.swift          NEW — one action, why, dismiss
Life/Coach/CoachExplanationSheet.swift NEW — evidence, sources, warnings
Life/Coach/AskCoachView.swift       NEW — chat, states, disclaimer, delete
Life/Coach/CoachBriefingView.swift  NEW — morning and evening
Life/Coach/CoachConsentView.swift   NEW — shown before the first cloud call
Life/TodayView.swift                EDIT — one card, everything else behind it
```

### Stage 4 — Settings and UI tests

```
Life/Coach/CoachSettingsSection.swift NEW — mirrors GoogleHealthSettingsSection
Life/SettingsView.swift             EDIT — one line to include it
LifeUITests/CoachUITests.swift      NEW — consent, disabled, Dynamic Type,
                                          VoiceOver, landscape
docs/life-coach-setup.md            NEW — key and deployment instructions
```

---

## 4. Open questions

1. **Blaze plan.** Firebase Functions needs pay-as-you-go enabled on the
   project. Nothing can be deployed until that's done.
2. **Model identifier.** Needed from Google's current docs at deploy time.
3. **Goals.** The brief's `CoachContext` includes a `goals` array. The app has
   no goals model beyond `goalWeightKg` and `stepGoal`. Stage 1 will derive
   goals from those; a real goals feature is out of scope unless asked for.

---

## 5. Explicitly out of scope

Per the brief: no unrelated features touched, no user data migrated or deleted,
no permissions granted automatically, nothing deployed without approval.
