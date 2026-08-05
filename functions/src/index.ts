import { initializeApp } from "firebase-admin/app";
import { onCall, HttpsError, CallableRequest } from "firebase-functions/v2/https";
import { defineSecret, defineString, defineInt } from "firebase-functions/params";
import { generateJSON, GeminiError } from "./gemini";
import {
  RECOMMENDATION_SCHEMA,
  BRIEFING_SCHEMA,
  validateRecommendation,
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

interface CoachRequestData {
  mode: Mode;
  context: unknown;
  question?: string;
  /** Set when a first attempt failed validation, so the retry can say why. */
  repairReason?: string;
}

/**
 * The system instruction.
 *
 * The rules that matter are enforced in code — the closed action list, the id
 * check, the URL rejection — because a model cannot be relied on to follow
 * instructions it is being actively prompted to break. These are here to shape
 * ordinary output, not to be the safety mechanism.
 */
const SYSTEM_INSTRUCTION = `
You are a wellbeing coach inside a personal app. You are given a compact,
already-cleaned summary of one person's recent health, training, tasks and
habits. You never see raw measurements and you must not recalculate anything.

Rules:
- Recommend exactly ONE next action. Never a list.
- Use plain, warm, direct language. British English. No exclamation marks.
- Justify the recommendation from the figures you were given, naming them.
- If a figure is marked low confidence, partial or missing, say so plainly and
  soften the advice. Never state a number you were not given.
- Missing data is not zero. If steps are absent, that means the tracker has not
  synced, not that the person did not move.
- Never diagnose, never name a condition, never mention medication or dosages.
- Do not draw dramatic conclusions from a single reading.
- If anything suggests a serious symptom, set safetyNotice advising they speak
  to a qualified professional, and keep the recommendation gentle.
- You are not a doctor and this is general wellbeing guidance.
- Only refer to a task or habit using an id that appears in the data you were
  given. Never invent an id.
- Never include links, URLs, code or commands.
`.trim();

const MODE_INSTRUCTIONS: Record<Mode, string> = {
  recommendation:
    "Give the single best next action for right now, with the evidence behind it.",
  morningBriefing:
    "Write a short morning briefing: how they slept, how recovered they are, what matters today, and one thing to focus on.",
  eveningReview:
    "Write a short evening review: what got done, how the day went for activity and training, and one lesson or suggestion for tomorrow.",
  ask: "Answer the question using only the data provided. If the data does not cover it, say so rather than guessing.",
};

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
        throw new HttpsError(
          error.kind === "cost" ? "resource-exhausted" : "resource-exhausted",
          error.message
        );
      }
      throw error;
    }

    const isBriefing = mode === "morningBriefing" || mode === "eveningReview";

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
        systemInstruction: SYSTEM_INSTRUCTION,
        userContent,
        responseSchema: isBriefing ? BRIEFING_SCHEMA : RECOMMENDATION_SCHEMA,
        maxOutputTokens: MAX_OUTPUT_TOKENS,
        temperature: 0.4,
        timeoutMs: REQUEST_TIMEOUT_MS,
      });

      const cost = await recordUsage(uid, result.usage, limits.pricing);

      if (!isBriefing) {
        const check = validateRecommendation(result.value);
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
      // Deliberately terse. The prompt contains the user's health summary and
      // the error body can echo it, so neither is logged or returned. Only the
      // status travels.
      if (error instanceof GeminiError) {
        throw new HttpsError("unavailable", `The coach is unavailable (${error.status}).`);
      }
      throw new HttpsError("unavailable", "The coach is unavailable.");
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
