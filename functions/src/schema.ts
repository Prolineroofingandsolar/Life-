/**
 * The shape the model must return, and the check that it did.
 *
 * Declared once and used twice: handed to Gemini as a response schema so it is
 * constrained at generation time, and enforced again here on the way back.
 * Both, not either — a schema tells the model what to produce but is not a
 * guarantee, and the app is about to act on this.
 */

/** Every action the app implements. Anything else is refused. */
export const ACTION_TYPES = [
  "completeTask",
  "scheduleTask",
  "rescheduleTask",
  "doPlannedWorkout",
  "reduceWorkoutIntensity",
  "takeWalk",
  "completeHabit",
  "rest",
  "logMissingData",
  "reviewGoal",
  "none",
] as const;

export const CATEGORIES = [
  "sleep",
  "recovery",
  "activity",
  "training",
  "tasks",
  "habits",
  "nutrition",
  "general",
] as const;

export const PRIORITIES = ["low", "medium", "high"] as const;
export const CONFIDENCES = ["low", "medium", "high"] as const;

export const MAX_HEADLINE_CHARS = 80;
export const MAX_SUMMARY_CHARS = 240;
export const MAX_EVIDENCE_ITEMS = 4;

/**
 * Gemini's response schema, in the OpenAPI subset it accepts.
 *
 * `relatedItemId` is nullable rather than optional: a model asked for an
 * optional field will sometimes omit it and sometimes invent one, and an
 * explicit null is easier to reason about than an absence.
 */
export const RECOMMENDATION_SCHEMA = {
  type: "OBJECT",
  properties: {
    headline: { type: "STRING" },
    summary: { type: "STRING" },
    category: { type: "STRING", enum: [...CATEGORIES] },
    actionType: { type: "STRING", enum: [...ACTION_TYPES] },
    relatedItemId: { type: "STRING", nullable: true },
    durationMinutes: { type: "INTEGER", nullable: true },
    priority: { type: "STRING", enum: [...PRIORITIES] },
    confidence: { type: "STRING", enum: [...CONFIDENCES] },
    evidence: {
      type: "ARRAY",
      items: {
        type: "OBJECT",
        properties: {
          label: { type: "STRING" },
          explanation: { type: "STRING" },
        },
        required: ["label", "explanation"],
      },
    },
    safetyNotice: { type: "STRING", nullable: true },
  },
  required: [
    "headline",
    "summary",
    "category",
    "actionType",
    "priority",
    "confidence",
    "evidence",
  ],
} as const;

export const BRIEFING_SCHEMA = {
  type: "OBJECT",
  properties: {
    headline: { type: "STRING" },
    body: { type: "STRING" },
    evidence: {
      type: "ARRAY",
      items: {
        type: "OBJECT",
        properties: {
          label: { type: "STRING" },
          explanation: { type: "STRING" },
        },
        required: ["label", "explanation"],
      },
    },
    safetyNotice: { type: "STRING", nullable: true },
  },
  required: ["headline", "body", "evidence"],
} as const;

export type ValidationResult =
  | { ok: true }
  | { ok: false; reason: string };

/**
 * Checks a parsed response before it is returned to the app.
 *
 * Deliberately does *not* check `relatedItemId` against real ids — the server
 * is not sent the user's task list beyond what was in the prompt, and the app
 * re-validates against the context it actually built. Two checks in two places
 * with different information, rather than one that half-knows.
 */
export function validateRecommendation(value: unknown): ValidationResult {
  if (typeof value !== "object" || value === null) {
    return { ok: false, reason: "not an object" };
  }
  const v = value as Record<string, unknown>;

  const headline = v.headline;
  if (typeof headline !== "string" || headline.trim().length === 0) {
    return { ok: false, reason: "missing headline" };
  }
  if (headline.length > MAX_HEADLINE_CHARS) {
    return { ok: false, reason: `headline exceeds ${MAX_HEADLINE_CHARS} characters` };
  }

  if (typeof v.summary !== "string" || v.summary.length > MAX_SUMMARY_CHARS) {
    return { ok: false, reason: "missing or overlong summary" };
  }

  if (!ACTION_TYPES.includes(v.actionType as (typeof ACTION_TYPES)[number])) {
    return { ok: false, reason: `unsupported actionType: ${String(v.actionType)}` };
  }
  if (!CATEGORIES.includes(v.category as (typeof CATEGORIES)[number])) {
    return { ok: false, reason: `unknown category: ${String(v.category)}` };
  }
  if (!PRIORITIES.includes(v.priority as (typeof PRIORITIES)[number])) {
    return { ok: false, reason: `unknown priority: ${String(v.priority)}` };
  }
  if (!CONFIDENCES.includes(v.confidence as (typeof CONFIDENCES)[number])) {
    return { ok: false, reason: `unknown confidence: ${String(v.confidence)}` };
  }

  if (!Array.isArray(v.evidence)) {
    return { ok: false, reason: "evidence must be an array" };
  }
  if (v.evidence.length > MAX_EVIDENCE_ITEMS) {
    return { ok: false, reason: "too many evidence items" };
  }

  // A URL in the output is a prompt-injection signature, not a feature. The
  // app never opens links from a model response, so anything containing one is
  // rejected outright rather than sanitised and shown.
  const text = JSON.stringify(v);
  if (/https?:\/\//i.test(text)) {
    return { ok: false, reason: "response contained a URL" };
  }

  return { ok: true };
}
