# Life Coach — what it doesn't do

Step 10 of the brief: remaining limitations and future improvements. Written
plainly, because a list of caveats nobody reads is worse than no list.

---

## Verified, and not

**Verified here:** the Cloud Functions typecheck clean under `strict`. I
installed the dependencies and ran the compiler.

**Not verified here:** every line of Swift. This repository is worked on from a
Linux container with no Swift toolchain and no Apple SDKs, so nothing in
`Life/` has been compiled or run by the author of this document. Three build
errors were found by the user rather than by me — a shadowed enum, an
actor-isolation violation in a default argument, and a `set` keyword collision.
Assume more of that kind exists until `scripts/build-and-test.sh` says
otherwise.

The tests are the only real verification available, and they have never been
executed. A green build is not a green suite.

---

## Known limitations

### The model identifier is unset

`GEMINI_MODEL` ships empty on purpose. Model names change often enough that a
hardcoded one is a scheduled outage, and this was written without the ability to
check Google's current list. **Until it is set, every call fails and the coach
falls back to local rules** — which looks like the feature working.

### The Gemini request shape is unproven

`functions/src/gemini.ts` follows the documented Generative Language REST API,
but no request has ever been sent. If the contract has moved, that one file is
where to correct it — it was kept isolated for exactly this reason.

### Costs are estimated, not measured

`GEMINI_INPUT_PRICE_PER_MILLION` and its output twin are configuration, not
truth. They drive the ceiling and the figure in Settings. If they're wrong, the
displayed spend is wrong — though the ceiling still stops *something*, just at a
different real amount than it says. Check them against current pricing.

### There is no goals model

The brief's `CoachContext` assumes named goals with ids and categories. Life has
five independent numeric targets — goal weight, step goal, sleep goal, active
minutes, habit targets — so the `goals` array is synthesised from those. A goal
like "run a 10k by March" cannot be expressed, and the coach cannot reason about
progress toward one.

### The step goal has no editor

Unrelated to the coach, found while building it: `careSettings.stepGoal` is
hardcoded to 10,000 in `Models.swift` and read in four places, but there is
nowhere in the app to change it. The coach inherits that, so its activity advice
is against a goal the user never chose.

### The coach proposes, it never acts

Ask Coach can now offer changes — add a task, complete one, log a habit or
water, plan a workout. Every one is a button. The model returns a description
of an intent; `CoachActions` is the only thing that performs one, it is only
reached from a tap, and it checks the proposal against real app data both
before the button is drawn and again before the change is made. There is no
path from a model response to a mutation that doesn't pass through a finger.

Five kinds are implemented. Editing a task's text, deleting anything, changing
goals or settings, and anything touching body or health records are all
deliberately absent — the first two because an undo stack doesn't exist yet,
the rest because they are the user's own measurements.

### Ask Coach has no memory

Each question is answered from the current context alone. It cannot follow up —
"what about last week?" after "how did I sleep?" starts again from scratch. The
conversation on screen is display only and is not sent.

### Feedback goes nowhere

"Was this useful?" is recorded in view state and discarded. The sheet says so.
It would need somewhere to accumulate before it could influence anything.

### Briefings need the app opened

The coach itself has no background refresh and no notification. A morning
briefing exists when you open the app before midday. The brief's "proactive" is
satisfied in the sense that it appears without being asked for, not in the sense
that it arrives.

Health data *is* now refreshed in the background (`HealthBackgroundRefresh`), so
the figures a briefing is built from are current when you open the app. Nothing
generates the briefing itself while the app is closed — that would mean a Gemini
call from a background wake-up, which is a cost and privacy decision worth
making deliberately rather than inheriting.

### Local rules are simple

Seven ordered rules. They will never spot that your sleep has drifted later over
three weeks, or that your training load and resting heart rate have been
diverging. They are a floor, not a substitute — but they are also the whole
feature for anyone who never enables AI, and worth extending on their own merit.

### Cost control is per user, not per device

The ceiling is enforced in Firestore against the Firebase uid, which is correct.
The *local* usage figure in Settings is per device, so two devices on one
account each show their own share and neither shows the total.

---

## Deliberate choices that could be revisited

**The merge never deletes.** A record deleted on one device returns if another
device still has it and hasn't synced. Chosen because a resurrected workout is
an annoyance and a deleted year of history is not recoverable. A tombstone
scheme would fix it properly.

**Task titles are off by default.** The coach can say "you have two important
tasks" but not which, until the switch is turned on. Cautious because a task
title routinely names a real person.

**One repair attempt, then local.** A second failure falls back rather than
trying again. Deliberate — the brief forbids repeated retries — but it does mean
a model having a bad minute costs that request entirely.

**Training load is session count, not volume.** Kilograms aren't comparable
across a leg day and an arm day, so totalling them would describe which muscles
were trained rather than how hard the week was. Cruder, but not misleading.

---

## Worth doing next, roughly in order

1. **Run the tests.** Everything else is speculation until this happens.
2. **Set `GEMINI_MODEL` and deploy.** Nothing AI-shaped works without it.
3. **Add a step goal editor.** Two lines in Settings ▸ Daily Care; it fixes a
   real gap the coach currently inherits.
4. **Compare the model against the local rules for a fortnight.** The fallback
   exists partly to make this comparison possible. If Gemini isn't beating seven
   `if` statements, that is worth knowing before paying for it indefinitely.
5. **Conversation memory for Ask Coach**, if it gets used.
6. **A real goals model**, if goals matter more than targets.
7. **Background briefings**, if the morning card isn't being seen.
