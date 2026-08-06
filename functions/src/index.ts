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
} from "./schema";
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
const MAX_OUTPUT_TOKENS = 700;
const REQUEST_TIMEOUT_MS = 20_000;

type Mode = "recommendation" | "morningBriefing" | "eveningReview" | "ask";

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
- Return an empty proposals array when there is nothing worth offering.
`.trim(),
};

/** The one-line reminder that leads the user content. */
const MODE_INSTRUCTIONS: Record<Mode, string> = {
  recommendation: "Give the single best next action for right now.",
  morningBriefing: "Write the morning briefing.",
  eveningReview: "Write the evening review.",
  ask: "Answer the question below using only the data provided.",
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

    const contextJSON = JSON.stringify(data?.context ?? {});
    if (contextJSON.length > MAX_CONTEXT_BYTES) {
      throw new HttpsError("invalid-argument", "The context was too large.");
    }

    const question = (data?.question ?? "").slice(0, MAX_QUESTION_CHARS);
    if (mode === "ask" && question.trim().length === 0) {
      throw new HttpsError("invalid-argument", "Ask a question first.");
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

    const isBriefing = mode === "morningBriefing" || mode === "eveningReview";
    const isAsk = mode === "ask";

    /** Each mode answers in its own shape. */
    const responseSchema = isBriefing
      ? BRIEFING_SCHEMA
      : isAsk
        ? ASK_SCHEMA
        : RECOMMENDATION_SCHEMA;

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
        responseSchema,
        maxOutputTokens: MAX_OUTPUT_TOKENS,
        temperature: 0.4,
        timeoutMs: REQUEST_TIMEOUT_MS,
      });

      const cost = await recordUsage(uid, result.usage, limits.pricing);

      if (!isBriefing) {
        const check = isAsk
          ? validateAsk(result.value)
          : validateRecommendation(result.value);
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
