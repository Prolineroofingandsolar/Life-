import { initializeApp } from "firebase-admin/app";
import { onCall, HttpsError, CallableRequest } from "firebase-functions/v2/https";
import { defineSecret, defineString, defineInt } from "firebase-functions/params";
import { generateJSON, GeminiError } from "./gemini";
import {
  RECOMMENDATION_SCHEMA,
  BRIEFING_SCHEMA,
  ASK_SCHEMA,
  validateRecommendation,
  validateAsk,
  ValidationResult,
} from "./schema";
import {
  WORKOUT_BLUEPRINT_SCHEMA,
  PLAN_BLUEPRINT_SCHEMA,
  MACHINE_SCHEMA,
  validateWorkoutBlueprint,
  validatePlanBlueprint,
  validateMachineIdentification,
  WEEKLY_REVIEW_SCHEMA,
  validateWeeklyReview,
  ADJUSTMENT_SCHEMA,
  validateAdjustment,
  PLATEAU_SCHEMA,
  validatePlateauAdvice,
} from "./workoutSchema";
import { reserveCall, recordUsage, readUsage, LimitExceeded } from "./limits";

initializeApp();

/**
 * The Gemini key. A Cloud Functions secret, so it exists in Secret Manager and
 * is injected at runtime — never in source, never in an env file that could be
 * committed, never in the app bundle.
 */
const GEMINI_API_KEY = defineSecret("GEMINI_API_KEY");

/**
 * Configurable so a more capable model can be swapped in for weekly plans
 * without a code change, and because model identifiers change often enough
 * that hardcoding one guarantees a future outage.
 */
const GEMINI_MODEL = defineString("GEMINI_MODEL");

const HOURLY_CALL_LIMIT = defineInt("COACH_HOURLY_CALLS", { default: 20 });
const MONTHLY_COST_CEILING = defineString("COACH_MONTHLY_COST_CEILING", {
  default: "1.00",
});
const INPUT_PRICE_PER_MILLION = defineString("GEMINI_INPUT_PRICE_PER_MILLION", {
  default: "0.10",
});
const OUTPUT_PRICE_PER_MILLION = defineString("GEMINI_OUTPUT_PRICE_PER_MILLION", {
  default: "0.40",
});
const COACH_ENABLED = defineString("COACH_ENABLED", { default: "true" });

/** Caps on what the app may send and what the model may return. */
const MAX_CONTEXT_BYTES = 12_000;
const MAX_QUESTION_CHARS = 500;
const REQUEST_TIMEOUT_MS = 20_000;

type Mode =
  | "recommendation"
  | "morningBriefing"
  | "eveningReview"
  | "ask"
  | "buildWorkout"
  | "buildPlan"
  | "identifyExercise"
  | "weeklyReview"
  | "adjustWorkout"
  | "plateauAdvice";

/**
 * Output budget, per mode.
 *
 * This was one shared constant of 700, which is ample for a coach tip and not
 * nearly enough for a plan. A four-session programme runs to roughly 1,800
 * output tokens; truncated at 700 it returns JSON that stops mid-object, and
 * `generateJSON` reports that as "response was not valid JSON" — an error which
 * blames the model for a limit we set. Per-mode, so a tip still costs a tip.
 */
const MAX_OUTPUT_TOKENS: Record<Mode, number> = {
  recommendation: 700,
  morningBriefing: 700,
  eveningReview: 700,
  ask: 700,
  buildWorkout: 900,
  buildPlan: 1800,
  // One small object. A generous ceiling here would only pay for prose nobody
  // reads.
  identifyExercise: 200,
  // Prose, but bounded prose: a headline, two paragraphs and at most three
  // actions.
  weeklyReview: 800,
  // One classification and a sentence.
  adjustWorkout: 200,
  // Three remedies and two sentences.
  plateauAdvice: 300,
};

/** Modes that carry a free-text brief or question in `question`. */
const MODES_REQUIRING_QUESTION: ReadonlySet<Mode> = new Set<Mode>([
  "ask", "buildWorkout", "buildPlan", "adjustWorkout", "plateauAdvice",
]);

/**
 * Logs a failure without logging what caused it to be sent.
 *
 * The distinction matters: the stack and the error's own message are safe and
 * are exactly what's needed to diagnose a problem, while the prompt is the
 * user's health summary and must never appear in a log that outlives the
 * request. Anything that isn't an Error is described by type only, because an
 * arbitrary thrown value could be a response body carrying the prompt back.
 */
/** What a Gemini status actually means, and what to do about it. */
function describeGeminiStatus(status: number): string {
  switch (status) {
    case 400:
      return "Gemini rejected the API key. Check the GEMINI_API_KEY secret.";
    case 401:
    case 403:
      return "Gemini refused the request. The API key may be revoked or restricted.";
    case 404:
      return "Gemini doesn't recognise that model. Check GEMINI_MODEL.";
    case 429:
      // Covers both the per-minute rate limit and an exhausted balance. The
      // distinction isn't visible in the status, so the message names both
      // rather than guessing at one.
      return "Gemini is out of quota or credit. Check billing in AI Studio, or wait a minute and retry.";
    case 500:
    case 503:
      return "Gemini is having trouble at their end. Try again shortly.";
    default:
      return `Gemini returned ${status}.`;
  }
}

function logFailure(stage: string, error: unknown): void {
  if (error instanceof Error) {
    console.error(`[coach:${stage}] ${error.name}: ${error.message}`, error.stack);
  } else {
    console.error(`[coach:${stage}] non-error thrown of type ${typeof error}`);
  }
}

interface CoachRequestData {
  mode: Mode;
  context: unknown;
  question?: string;
  /** Set when a first attempt failed validation, so the retry can say why. */
  repairReason?: string;
  /**
   * A base64 JPEG, for `identifyExercise` only.
   *
   * Never logged, never persisted, never echoed back. It exists for the length
   * of one request and then it is gone.
   */
  image?: string;
  imageMimeType?: string;
}

/**
 * The rules that apply to every mode.
 *
 * The rules that *matter* are enforced in code — the closed action list, the id
 * check, the URL rejection — because a model cannot be relied on to follow
 * instructions it is being actively prompted to break. These shape ordinary
 * output; they are not the safety mechanism.
 *
 * Note what is no longer here: "recommend exactly ONE next action". That is the
 * recommendation mode's job and nobody else's, and applying it globally is why
 * a morning briefing kept ending in a nagging instruction and why Ask Coach
 * answered "what changed since yesterday?" with a suggestion instead of an
 * answer. Each mode's own instruction now says what that mode is for.
 */
const BASE_INSTRUCTION = `
You are a wellbeing coach inside a personal app. You are given a compact,
already-cleaned summary of one person's recent health, training, tasks and
habits. You never see raw measurements and you must not recalculate anything.

Language:
- Plain, warm, direct. British English throughout. No exclamation marks.
- Format durations the way a person says them: "7h 51m", never "471 minutes"
  and never "7.85 hours". If the data gives you both a number and a formatted
  version of it, use the formatted version.
- Do not repeat every figure you were given. Name the ones that carry the point.

Honesty about the data:
- Distinguish three different things and never blur them: a MEASUREMENT (what
  a device recorded), a CALCULATED TREND or score (what the app worked out from
  measurements), and a RECOMMENDATION (what you think they should do).
- Missing data is not zero. If steps are absent, the tracker has not synced —
  it does not mean the person did not move.
- Each figure carries a "state". Say what it means, in these words or close to
  them:
    missing              → there is no measurement
    stale                → there is a measurement but it is not from today
    insufficientHistory  → there IS a measurement, but not enough past readings
                           to say whether it is high or low for this person.
                           Say "not enough history to assess recovery". Never
                           say "no recovery data" when a reading exists — the
                           person can see that reading on the Health screen, and
                           denying it makes the whole app look broken.
    partial              → recorded incompletely, or still accumulating today
    ready                → a current reading with enough behind it to interpret
- A score is a number, not a state of mind. Never call a score "high
  confidence". Confidence describes the DATA behind a figure, not the figure.
  "A readiness score of 74, from high-confidence data" is right; "a readiness
  score of 74, high confidence" is not.
- If two facts appear to conflict, explain why rather than picking one. A
  resting heart rate that is recorded but not yet interpretable is not a
  contradiction; it is a measurement without a baseline, and saying so is the
  answer.
- Never state a number you were not given.
- Say what additional data would materially change your advice, when there is
  something specific — a few more nights, a synced tracker, a logged workout.

Safety:
- Never diagnose, never name a condition, never mention medication or dosages.
- Do not draw dramatic conclusions from a single reading.
- If anything suggests a serious symptom, set safetyNotice advising they speak
  to a qualified professional, and keep your advice gentle.
- You are not a doctor and this is general wellbeing guidance.

Boundaries:
- Only refer to a task, habit or routine using an id that appears in the data
  you were given. Never invent an id.
- Never include links, URLs, code or commands.
- You never change anything. Anything you propose is a button the person taps.
`.trim();

/**
 * What each mode is *for*, appended to the shared rules above.
 *
 * Kept as full system instructions rather than a line of user content, because
 * a mode's job is a standing constraint on the whole response and not a request
 * within it.
 */
const MODE_SYSTEM_INSTRUCTIONS: Record<Mode, string> = {
  recommendation: `
Your job: the single best next action for right now.

- Exactly ONE action. Never a list. Choosing is the entire value you add over
  the numbers already on the screen.
- Prefer a concrete conclusion to a menu. "Do the 20-minute walk now" beats
  "you could go for a walk, or you could rest".
- Justify it from the figures you were given, naming them.
- If the data is too thin to choose well, say so and pick the action that fixes
  that — checking the tracker has synced is a legitimate next action.
`.trim(),

  morningBriefing: `
Your job: a short morning briefing. Two or three sentences.

- How they slept, how recovered they look, and the one thing worth their
  attention today.
- This is a summary, not an instruction. Do not end with a command, and do not
  duplicate the app's separate next-action card by issuing a second one.
- Do not open with a greeting. The screen already says good morning; saying it
  again is the app talking over itself.
- If last night was not recorded, say that plainly rather than describing an
  older night as though it were last night.
`.trim(),

  eveningReview: `
Your job: a short evening review. Two or three sentences.

- What got done, how the day went for activity and training, and one thing to
  carry into tomorrow.
- Look back, not forward. This is not the place for a next action.
- Judge the day against what the data actually covers. A day the tracker did
  not sync is a day you know little about, not a day nothing happened.
`.trim(),

  identifyExercise: `
Your job: name the piece of gym equipment in the photograph.

- Give the movement it is used for, not the manufacturer's product name. "Lat
  pulldown", not "Cybex VR3 Pulldown".
- Pick the muscle and equipment values from the lists in the schema. If the
  photo shows a cable stack, that is "cable"; a selectorised machine is
  "machine"; free weights are "barbell" or "dumbbell".
- confidence is 0-100 and should be honest. A clear photo of a familiar machine
  is high; a dark corner of a gym is not. The app shows your figure to the
  person rather than hiding a poor guess, so a low number is useful and a
  dishonest high one is not.
- If the photograph does not show gym equipment at all, still answer in the
  schema, with a confidence at or below 10.
- Say nothing about any person in the photograph. Not their build, not their
  form, not their presence. You are looking at a machine.
`.trim(),

  ask: `
Your job: answer the question that was asked, from the data you were given.

Structure every answer in this order:
1. A DIRECT ANSWER FIRST, in the first sentence: yes, no, likely, unlikely, or
   not enough data. Do not build up to it.
2. At most THREE short evidence points. Fewer is better. Only the figures that
   actually bear on the question.
3. A plain statement of what is missing, stale, partial or low-confidence in
   the data you used — and if nothing is, say the data covers the question.
4. At most ONE suggested action, and only when the question calls for one. A
   question is usually a question.

- If the data does not cover the question, say so in the first sentence and
  stop. Do not answer a nearby question instead.
- Never invent an answer. There is no local fallback behind you: a wrong answer
  is shown to the person as though it were checked.

Proposals (the buttons under your answer):
- Up to three, and usually zero. Offer one only when the question plainly calls
  for it — a wall of buttons under every answer is noise.
- Never offer to complete a task or log a habit the person has not asked about.
  Doing something on their behalf is their decision; you are proposing, not
  acting.
- Use ids exactly as they appear in the data and never invent one. Omit
  targetId if you do not have a real one.
- buildWorkout is for when the person asks what to train, or for a session, and
  no existing routine fits. Put the brief in your own words in title — what to
  work, how hard, anything to avoid — and minutes in count if they said how long
  they have. NEVER name an exercise in title: the app owns the exercise library
  and chooses the movements itself. It opens a builder that asks its own
  questions, so an incomplete brief costs nothing.
- Prefer planWorkout over buildWorkout when a routine in the data already does
  the job. Building a new session when they already have one is work you made
  for them.
- Return an empty proposals array when there is nothing worth offering.
`.trim(),

  buildWorkout: `
Your job: describe the SHAPE of one training session. You do not name exercises.

- You never write the name of a movement. Not in a slot, not in the session
  name, not in the notes. The app owns this person's exercise library and picks
  the movement for each slot itself. Naming one would be guessing at a library
  you cannot see, and the app would have to throw your answer away.
- Each slot is a muscle group, optionally an equipment preference and a movement
  type, then sets, a rep range, a rest period and optionally reps in reserve.
- Only use muscle groups that appear in the library figures you were given. A
  muscle with a count of zero has nothing behind it — asking for it wastes a
  slot the person will never see.
- Compounds before isolation. Largest muscle groups first.
- Read the recovery figures. A muscle at 70% fatigue or above was trained hard
  and recently: leave it alone unless the person explicitly asked for it, and
  say why in the notes if you use it anyway. Fatigue of zero with hasHistory
  false means never trained, NOT fully recovered — treat it as unknown.
- Prefer muscles below their weekly set target over ones already above it.
- Between three and eight slots for a typical session. Respect the time budget
  you were given: roughly one slot per seven minutes.
- "name" is a label for the session — "Upper Body — Strength", "Push A". It is
  never a movement.
- Do not estimate a duration. The app calculates it exactly and will show its
  own figure.
`.trim(),

  weeklyReview: `
Your job: say what this training week was, and what — if anything — to change.

Every figure below was calculated by the app. Do not recalculate, do not round
into a different number, and do not contradict one.

- Lead with what matters. Do not narrate the statistics in order; two figures
  that carry the point beat eight that don't.
- At most three actions, often fewer, and "keepUnchanged" is a real answer. A
  good week needs no changes and saying so is more useful than finding
  something.
- Every action's rationale must cite a figure you were given.
- adherencePercent may be absent. That means nothing was planned, NOT that
  nothing was done — never describe it as poor adherence.
- A week with one or two sessions is a small sample. Say so rather than drawing
  a trend from it.
- No medical claims. Tiredness, soreness and pain are not yours to explain.
`.trim(),

  adjustWorkout: `
Your job: turn one sentence into one adjustment, and nothing else.

- Pick exactly one kind: shorten, equipmentOnly, lighter, or avoid.
- "I've only got half an hour" with a 50-minute session is shorten, minutes 20.
- "Only dumbbells today" is equipmentOnly.
- "I'm shattered", "go easy" is lighter.
- "My shoulder hurts", "nothing overhead" is avoid, with the muscle group.
- If pain or injury is mentioned, choose avoid for the affected group and say in
  the explanation that this only removes exercises — it is not medical advice
  and persistent pain is worth a professional's opinion. Do not name a
  condition, and do not suggest a treatment.
- If the request fits none of these, choose lighter and say in the explanation
  that you weren't sure, so the person can see what you did and undo it.
- The explanation is one sentence, in their words, about what will change.
`.trim(),

  plateauAdvice: `
Your job: suggest what to try about a lift that has stopped progressing.

- Pick at most three remedies from the list you are given. Fewer is better.
- NEVER say why it stalled. You do not know, and neither does the app. No
  physiological explanation, no mention of overtraining, recovery, hormones,
  sleep or injury — not even to rule one out. A response that reaches for a
  cause will be rejected outright.
- Describe what each remedy would mean in practice, in one sentence total.
- If the numbers show the lift going down rather than sideways, say that plainly
  and prefer the lighter-week remedy.
- Do not be encouraging about it. A plateau is ordinary; treating it as a crisis
  or as a triumph both misread it.
`.trim(),

  buildPlan: `
Your job: describe the SHAPE of a training week, to be repeated.

Everything in the buildWorkout instructions applies to each session here.

- "sessions" are the distinct sessions in a typical week. "weekdays" schedules
  them, 1 being Monday. A weekday with no sessionKey is a rest day.
- The same week repeats for "weeks". You cannot describe a different week three
  — the app schedules a repeating week and cannot enact variation between them.
  Put the week-to-week intent in "progression" as one sentence the person reads.
- Match the number of training days to what was asked for. Do not add a session
  because it would be better; the days they gave you are the days they have.
- Leave at least one rest day between sessions that work the same large muscle
  group.
- Think in WEEKLY volume, not per-session variety. A muscle trained once a week
  needs three or four slots on that day, not one. A "legs" day made of one leg
  slot plus glutes, calves and core gives legs three or four sets for the whole
  week, which is a third of what it needs — name the primary muscle repeatedly
  in the same session instead.
- Put the primary muscle's slots first in the session. Sessions get truncated to
  fit the time budget, and the accessories are what should be lost.
`.trim(),
};

/** Each mode answers in its own shape. */
const RESPONSE_SCHEMAS: Record<Mode, unknown> = {
  recommendation: RECOMMENDATION_SCHEMA,
  morningBriefing: BRIEFING_SCHEMA,
  eveningReview: BRIEFING_SCHEMA,
  ask: ASK_SCHEMA,
  buildWorkout: WORKOUT_BLUEPRINT_SCHEMA,
  buildPlan: PLAN_BLUEPRINT_SCHEMA,
  identifyExercise: MACHINE_SCHEMA,
  weeklyReview: WEEKLY_REVIEW_SCHEMA,
  adjustWorkout: ADJUSTMENT_SCHEMA,
  plateauAdvice: PLATEAU_SCHEMA,
};

/**
 * The second gate, per mode.
 *
 * Briefings have no validator: they are prose in a fixed envelope with nothing
 * the app will act on, so there is no content claim to check. Everything that
 * can reach a button or a saved record has one.
 */
const VALIDATORS: Partial<Record<Mode, (value: unknown) => ValidationResult>> = {
  recommendation: validateRecommendation,
  ask: validateAsk,
  buildWorkout: validateWorkoutBlueprint,
  buildPlan: validatePlanBlueprint,
  identifyExercise: validateMachineIdentification,
  weeklyReview: validateWeeklyReview,
  adjustWorkout: validateAdjustment,
  plateauAdvice: validatePlateauAdvice,
};

/** The one-line reminder that leads the user content. */
const MODE_INSTRUCTIONS: Record<Mode, string> = {
  recommendation: "Give the single best next action for right now.",
  morningBriefing: "Write the morning briefing.",
  eveningReview: "Write the evening review.",
  ask: "Answer the question below using only the data provided.",
  buildWorkout: "Describe the shape of one session matching the brief below.",
  buildPlan: "Describe the shape of a training week matching the brief below.",
  identifyExercise: "Identify the gym machine or equipment in this photograph.",
  weeklyReview: "Review the training week described in the data below.",
  adjustWorkout: "Turn the request below into one adjustment.",
  plateauAdvice: "Suggest what to try about the stalled lift described below.",
};

function systemInstruction(mode: Mode): string {
  return `${BASE_INSTRUCTION}\n\n${MODE_SYSTEM_INSTRUCTIONS[mode]}`;
}

export const coach = onCall(
  {
    secrets: [GEMINI_API_KEY],
    region: "europe-west2",
    // Small and short. This is one user's occasional request, not a service.
    memory: "256MiB",
    timeoutSeconds: 60,
    maxInstances: 3,
  },
  async (request: CallableRequest<CoachRequestData>) => {
    // The whole reason for choosing callable functions. No token parsing, no
    // key verification to get wrong — an unauthenticated caller cannot reach
    // the model, and therefore cannot spend the key.
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "Sign in to use the coach.");
    }
    const uid = request.auth.uid;

    if (COACH_ENABLED.value().toLowerCase() !== "true") {
      throw new HttpsError("failed-precondition", "The coach is switched off.");
    }

    const data = request.data;
    const mode: Mode = data?.mode ?? "recommendation";
    if (!(mode in MODE_INSTRUCTIONS)) {
      throw new HttpsError("invalid-argument", "Unknown coach mode.");
    }

    // Checked before anything else is attempted. An unset model produces a
    // request to `/models/:generateContent`, whose 404 reads as a broken
    // integration rather than a missing line in an env file.
    if (!GEMINI_MODEL.value()) {
      throw new HttpsError(
        "failed-precondition",
        "GEMINI_MODEL isn't set. Add it to functions/.env.<project> and redeploy."
      );
    }

    if (mode === "identifyExercise" && !data?.image) {
      throw new HttpsError("invalid-argument", "No photo was included.");
    }

    const contextJSON = JSON.stringify(data?.context ?? {});
    if (contextJSON.length > MAX_CONTEXT_BYTES) {
      throw new HttpsError("invalid-argument", "The context was too large.");
    }

    const question = (data?.question ?? "").slice(0, MAX_QUESTION_CHARS);
    if (MODES_REQUIRING_QUESTION.has(mode) && question.trim().length === 0) {
      throw new HttpsError(
        "invalid-argument",
        mode === "ask" ? "Ask a question first." : "Say what you'd like built."
      );
    }

    const limits = {
      hourlyCalls: HOURLY_CALL_LIMIT.value(),
      monthlyCostCeiling: Number(MONTHLY_COST_CEILING.value()),
      pricing: {
        inputPerMillion: Number(INPUT_PRICE_PER_MILLION.value()),
        outputPerMillion: Number(OUTPUT_PRICE_PER_MILLION.value()),
      },
    };

    try {
      await reserveCall(uid, limits);
    } catch (error) {
      if (error instanceof LimitExceeded) {
        throw new HttpsError("resource-exhausted", error.message);
      }
      // Anything else here is a Firestore problem — a missing database, or a
      // service account without write access. Rethrowing raw surfaced it to the
      // app as a bare "INTERNAL", which tells the user nothing and tells whoever
      // is debugging it even less.
      logFailure("reserveCall", error);
      throw new HttpsError(
        "internal",
        "Couldn't record usage before calling the coach. Check the function logs."
      );
    }

    const userContent = [
      MODE_INSTRUCTIONS[mode],
      question ? `Question: ${question}` : "",
      data?.repairReason
        ? `A previous attempt was rejected because: ${data.repairReason}. Correct it.`
        : "",
      "Data:",
      contextJSON,
    ]
      .filter(Boolean)
      .join("\n\n");

    try {
      const result = await generateJSON({
        apiKey: GEMINI_API_KEY.value(),
        model: GEMINI_MODEL.value(),
        systemInstruction: systemInstruction(mode),
        userContent,
        responseSchema: RESPONSE_SCHEMAS[mode],
        inlineImageBase64: mode === "identifyExercise" ? data?.image : undefined,
        inlineImageMimeType: data?.imageMimeType,
        maxOutputTokens: MAX_OUTPUT_TOKENS[mode],
        // Lower for generation than for prose. A workout is a structured
        // prescription, and variety in it is noise rather than voice — the same
        // brief on two days should not produce two materially different plans.
        temperature: mode === "buildWorkout" || mode === "buildPlan" ? 0.2 : 0.4,
        timeoutMs: REQUEST_TIMEOUT_MS,
      });

      const cost = await recordUsage(uid, result.usage, limits.pricing);

      const validator = VALIDATORS[mode];
      if (validator) {
        const check = validator(result.value);
        if (!check.ok) {
          // Reported as data, not thrown. The app decides whether to ask for a
          // repair or fall back to its local suggestion, and it needs the
          // reason to do either.
          return {
            ok: false,
            reason: check.reason,
            usage: { ...result.usage, cost },
          };
        }
      }

      return {
        ok: true,
        value: result.value,
        usage: { ...result.usage, cost },
      };
    } catch (error) {
      // Deliberately terse to the *client*. The prompt contains the user's
      // health summary and an error body can echo it, so neither is returned.
      // The log gets the error's type and message but never the prompt.
      if (error instanceof HttpsError) throw error;

      if (error instanceof GeminiError) {
        logFailure("gemini", error);
        // Each status has a different cause and a different fix, and telling
        // someone to check their API key when the real problem is an empty
        // billing account sends them looking in the wrong place entirely.
        throw new HttpsError("unavailable", describeGeminiStatus(error.status));
      }

      logFailure("generate", error);
      const detail = error instanceof Error ? error.name : "unknown error";
      throw new HttpsError("unavailable", `The coach is unavailable (${detail}).`);
    }
  }
);

/** Current month's usage, for the settings screen. */
export const coachUsage = onCall(
  { region: "europe-west2", memory: "256MiB", maxInstances: 3 },
  async (request: CallableRequest<unknown>) => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "Sign in to use the coach.");
    }
    const usage = await readUsage(request.auth.uid);
    return {
      ...usage,
      monthlyCostCeiling: Number(MONTHLY_COST_CEILING.value()),
    };
  }
);
