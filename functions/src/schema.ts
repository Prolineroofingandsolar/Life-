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

/**
 * The changes the coach may *offer* to make.
 *
 * Offer, not make. The brief this feature was built to is explicit that the
 * coach never modifies tasks, training or goals on its own, and nothing here
 * relaxes that: a proposal is a button the person taps, and the app is what
 * performs the change. The model produces a description of an intent, never an
 * instruction that executes.
 *
 * Closed for the same reason `ACTION_TYPES` is closed. Every entry corresponds
 * to a method the app already exposes, and an unrecognised one is refused
 * rather than ignored — a proposal the app can't perform must not reach a
 * button that appears to perform it.
 */
export const PROPOSAL_TYPES = [
  "addTask",
  "completeTask",
  "addHabitLog",
  "logWater",
  "planWorkout",
  /**
   * Opens the workout builder with the brief in `title`. The only proposal type
   * that performs no change at all: the app presents the builder, asks its own
   * questions and requires a second confirmation before anything is written.
   */
  "buildWorkout",
] as const;

export const MAX_PROPOSALS = 3;
export const MAX_ANSWER_CHARS = 1200;
export const MAX_PROPOSAL_TITLE_CHARS = 80;

/**
 * The answer to a question, plus anything the coach offers to do about it.
 *
 * `proposals` is required rather than optional so "nothing to offer" is an
 * empty array the model has to produce deliberately, not an absence that could
 * equally mean it forgot.
 */
export const ASK_SCHEMA = {
  type: "OBJECT",
  properties: {
    summary: { type: "STRING" },
    proposals: {
      type: "ARRAY",
      items: {
        type: "OBJECT",
        properties: {
          type: { type: "STRING", enum: [...PROPOSAL_TYPES] },
          /** What the button says. Imperative: "Add 'Call the plumber'". */
          label: { type: "STRING" },
          /**
           * For addTask and planWorkout. For buildWorkout, the brief in your
           * own words — never an exercise name.
           */
          title: { type: "STRING", nullable: true },
          /** For addTask: one of the app's list ids, from the context. */
          listId: { type: "STRING", nullable: true },
          /** For addTask: today, tomorrow or thisWeek. */
          due: { type: "STRING", enum: ["today", "tomorrow", "thisWeek"], nullable: true },
          /** For completeTask, addHabitLog, planWorkout: an id from the data. */
          targetId: { type: "STRING", nullable: true },
          /** For logWater and addHabitLog. For buildWorkout, minutes. */
          count: { type: "INTEGER", nullable: true },
        },
        required: ["type", "label"],
      },
    },
    safetyNotice: { type: "STRING", nullable: true },
  },
  required: ["summary", "proposals"],
} as const;

/**
 * Checks an answer before it is returned.
 *
 * Proposals are checked for shape and for a closed type only. Whether a
 * `targetId` names a real task is checked in the app, which is the side that
 * holds the task list — the server sees only what was in the prompt, so a check
 * here would be a guess dressed as a guarantee.
 */
export function validateAsk(value: unknown): ValidationResult {
  if (typeof value !== "object" || value === null) {
    return { ok: false, reason: "not an object" };
  }
  const v = value as Record<string, unknown>;

  if (typeof v.summary !== "string" || v.summary.trim().length === 0) {
    return { ok: false, reason: "missing answer" };
  }
  if (v.summary.length > MAX_ANSWER_CHARS) {
    return { ok: false, reason: `answer exceeds ${MAX_ANSWER_CHARS} characters` };
  }

  const proposals = v.proposals ?? [];
  if (!Array.isArray(proposals)) {
    return { ok: false, reason: "proposals must be an array" };
  }
  if (proposals.length > MAX_PROPOSALS) {
    return { ok: false, reason: `more than ${MAX_PROPOSALS} proposals` };
  }

  for (const raw of proposals) {
    if (typeof raw !== "object" || raw === null) {
      return { ok: false, reason: "proposal is not an object" };
    }
    const p = raw as Record<string, unknown>;
    if (!PROPOSAL_TYPES.includes(p.type as (typeof PROPOSAL_TYPES)[number])) {
      return { ok: false, reason: `unsupported proposal type: ${String(p.type)}` };
    }
    if (typeof p.label !== "string" || p.label.trim().length === 0) {
      return { ok: false, reason: "proposal has no label" };
    }
    if (p.label.length > MAX_PROPOSAL_TITLE_CHARS) {
      return { ok: false, reason: "proposal label too long" };
    }
    if (p.title !== undefined && p.title !== null) {
      if (typeof p.title !== "string" || p.title.length > MAX_PROPOSAL_TITLE_CHARS) {
        return { ok: false, reason: "proposal title too long" };
      }
    }
  }

  // Same reasoning as the recommendation check: a URL in a model response is a
  // prompt-injection signature, not a feature.
  if (/https?:\/\//i.test(JSON.stringify(v))) {
    return { ok: false, reason: "response contained a URL" };
  }

  return { ok: true };
}

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
