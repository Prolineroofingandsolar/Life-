/**
 * The shape a generated workout must take, and the check that it did.
 *
 * The rule this file exists to enforce: **the model describes the shape of a
 * session, and never names a movement.** It emits a slot — a muscle group, an
 * optional equipment preference, sets, a rep range, a rest period — and the app
 * resolves that slot to a real exercise from the user's own library.
 *
 * That is not a stylistic preference. The app holds 187 seeded exercises with
 * stable ids, and a model asked to name one has no way to know which ids exist.
 * Any name it produced would be resolved by string matching on the client, and
 * a miss would either drop the exercise or manufacture a new record — the exact
 * failure mode the CSV importer has and the reason it is quarantined.
 *
 * Enforced three ways, deliberately overlapping:
 *
 * 1. Closed enums in the response schema, so the model is constrained at
 *    generation time.
 * 2. A **strict key whitelist** per slot in the validators below. A response
 *    carrying `"exerciseName": "Bench Press"` is rejected *whole* rather than
 *    having the field quietly dropped, because a model that tried to name a
 *    movement has misunderstood the task and its other slots are suspect too.
 * 3. Strict `Codable` on the client, which throws on an unknown enum value.
 *
 * A schema tells the model what to produce. It is not a guarantee, which is why
 * everything here is checked again in code.
 */

import type { ValidationResult } from "./schema";

/**
 * The muscle vocabulary, closed.
 *
 * Must stay in step with `Exercise.muscle` in `Life/WorkoutSeed.swift` and with
 * `BlueprintMuscle` in `Life/Coach/WorkoutBlueprint.swift`. Nothing enforces
 * that across the language boundary, so a Swift test asserts the three agree —
 * a muscle the model can ask for but Swift cannot resolve silently loses that
 * slot, and presents as "the coach keeps forgetting my calves".
 */
export const MUSCLES = [
  "Back", "Biceps", "Calves", "Cardio", "Chest",
  "Core", "Glutes", "Legs", "Shoulders", "Triceps",
] as const;

/** Mirrors `ExerciseEquipment` in `Life/Models.swift`. */
export const EQUIPMENT = [
  "barbell", "dumbbell", "cable", "machine",
  "bodyweight", "kettlebell", "band", "ezBar", "other",
] as const;

/** Mirrors `MovementType` in `Life/Models.swift`. */
export const MOVEMENT_TYPES = ["compound", "isolation", "cardio"] as const;

// Bounds. Every one of these is a number a model can get wrong in a way that
// produces a plausible-looking response and an unusable workout.
export const MIN_SLOTS = 2;
export const MAX_SLOTS = 10;
export const MAX_TOTAL_SETS = 40;
export const MAX_SETS_PER_SLOT = 6;
export const MAX_REPS = 50;
export const MIN_REST_SECONDS = 15;
export const MAX_REST_SECONDS = 300;
export const MAX_RIR = 5;

export const MAX_PLAN_WEEKS = 12;
export const MAX_PLAN_SESSIONS = 6;
export const MAX_NAME_CHARS = 48;
export const MAX_NOTE_CHARS = 240;

/**
 * The only keys a slot may carry.
 *
 * Anything else — most importantly a movement name — fails the whole response.
 */
const ALLOWED_SLOT_KEYS = new Set([
  "muscle", "movementType", "equipment", "sets",
  "repMin", "repMax", "restSeconds", "rir", "supersetGroup",
]);

const SLOT_SCHEMA = {
  type: "OBJECT",
  properties: {
    muscle: { type: "STRING", enum: [...MUSCLES] },
    movementType: { type: "STRING", enum: [...MOVEMENT_TYPES], nullable: true },
    equipment: { type: "STRING", enum: [...EQUIPMENT], nullable: true },
    sets: { type: "INTEGER" },
    repMin: { type: "INTEGER" },
    repMax: { type: "INTEGER" },
    restSeconds: { type: "INTEGER" },
    /** Reps in reserve. Guidance the app can show without knowing a load. */
    rir: { type: "INTEGER", nullable: true },
    /** Slots sharing a number are performed back to back. */
    supersetGroup: { type: "INTEGER", nullable: true },
  },
  required: ["muscle", "sets", "repMin", "repMax", "restSeconds"],
} as const;

/**
 * One session.
 *
 * Note what is deliberately absent: **an estimated duration**. The app can
 * compute that exactly from sets, reps and rest, and a model-supplied minute
 * count is an unverifiable number the preview would have to either display or
 * silently ignore. Neither is good, so it is never asked for.
 */
export const WORKOUT_BLUEPRINT_SCHEMA = {
  type: "OBJECT",
  properties: {
    /** A label for the session — "Upper Body — Strength". Never a movement. */
    name: { type: "STRING" },
    focus: { type: "STRING" },
    slots: { type: "ARRAY", items: SLOT_SCHEMA },
    notes: { type: "STRING", nullable: true },
  },
  required: ["name", "focus", "slots"],
} as const;

/**
 * A repeating week, plus how many weeks to run it for.
 *
 * One session set, repeated — not a different week three. True periodisation
 * isn't expressible in the app's `WorkoutProgram`, which is a weekly split, and
 * a schema that let the model describe something the app cannot enact would
 * produce drafts that fail on save. `progression` carries the week-to-week
 * intent as prose the person reads instead.
 */
export const PLAN_BLUEPRINT_SCHEMA = {
  type: "OBJECT",
  properties: {
    name: { type: "STRING" },
    weeks: { type: "INTEGER" },
    sessions: {
      type: "ARRAY",
      items: {
        type: "OBJECT",
        properties: {
          key: { type: "STRING" },
          blueprint: WORKOUT_BLUEPRINT_SCHEMA,
        },
        required: ["key", "blueprint"],
      },
    },
    weekdays: {
      type: "ARRAY",
      items: {
        type: "OBJECT",
        properties: {
          /** 1 = Monday, matching `ProgramDay.weekday`. */
          weekday: { type: "INTEGER" },
          sessionKey: { type: "STRING", nullable: true },
        },
        required: ["weekday"],
      },
    },
    progression: { type: "STRING", nullable: true },
  },
  required: ["name", "weeks", "sessions", "weekdays"],
} as const;

// MARK: - Validation

function fail(reason: string): ValidationResult {
  return { ok: false, reason };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function checkText(
  value: unknown, field: string, max: number, required: boolean
): ValidationResult | null {
  if (value === undefined || value === null) {
    return required ? fail(`missing ${field}`) : null;
  }
  if (typeof value !== "string") return fail(`${field} is not a string`);
  if (required && value.trim().length === 0) return fail(`empty ${field}`);
  if (value.length > max) return fail(`${field} exceeds ${max} characters`);
  return null;
}

function checkInt(
  value: unknown, field: string, min: number, max: number
): ValidationResult | null {
  if (typeof value !== "number" || !Number.isInteger(value)) {
    return fail(`${field} is not a whole number`);
  }
  if (value < min || value > max) {
    return fail(`${field} must be between ${min} and ${max}`);
  }
  return null;
}

/**
 * Checks one slot.
 *
 * The key whitelist runs first and is the load-bearing check. Everything after
 * it is range-checking a model that at least understood the assignment.
 */
function validateSlot(raw: unknown, index: number): ValidationResult | null {
  if (!isRecord(raw)) return fail(`slot ${index} is not an object`);

  for (const key of Object.keys(raw)) {
    if (!ALLOWED_SLOT_KEYS.has(key)) {
      // The one that matters. A model naming a movement here has misunderstood
      // what it was asked for, and the rest of its answer cannot be trusted.
      return fail(`slot ${index} carried an unexpected field: ${key}`);
    }
  }

  if (!MUSCLES.includes(raw.muscle as (typeof MUSCLES)[number])) {
    return fail(`slot ${index} has an unknown muscle: ${String(raw.muscle)}`);
  }
  if (raw.movementType !== undefined && raw.movementType !== null &&
      !MOVEMENT_TYPES.includes(raw.movementType as (typeof MOVEMENT_TYPES)[number])) {
    return fail(`slot ${index} has an unknown movement type`);
  }
  if (raw.equipment !== undefined && raw.equipment !== null &&
      !EQUIPMENT.includes(raw.equipment as (typeof EQUIPMENT)[number])) {
    return fail(`slot ${index} has unknown equipment`);
  }

  const setsError = checkInt(raw.sets, `slot ${index} sets`, 1, MAX_SETS_PER_SLOT);
  if (setsError) return setsError;

  const repMinError = checkInt(raw.repMin, `slot ${index} repMin`, 1, MAX_REPS);
  if (repMinError) return repMinError;

  const repMaxError = checkInt(raw.repMax, `slot ${index} repMax`, 1, MAX_REPS);
  if (repMaxError) return repMaxError;

  if ((raw.repMin as number) > (raw.repMax as number)) {
    return fail(`slot ${index} has a rep range that runs backwards`);
  }

  const restError = checkInt(
    raw.restSeconds, `slot ${index} restSeconds`, MIN_REST_SECONDS, MAX_REST_SECONDS
  );
  if (restError) return restError;

  if (raw.rir !== undefined && raw.rir !== null) {
    const rirError = checkInt(raw.rir, `slot ${index} rir`, 0, MAX_RIR);
    if (rirError) return rirError;
  }

  if (raw.supersetGroup !== undefined && raw.supersetGroup !== null) {
    const groupError = checkInt(raw.supersetGroup, `slot ${index} supersetGroup`, 1, MAX_SLOTS);
    if (groupError) return groupError;
  }

  return null;
}

/** Checks one session blueprint. Shared by the workout and plan validators. */
export function validateWorkoutBlueprint(value: unknown): ValidationResult {
  if (!isRecord(value)) return fail("not an object");

  const nameError = checkText(value.name, "name", MAX_NAME_CHARS, true);
  if (nameError) return nameError;

  const focusError = checkText(value.focus, "focus", MAX_NOTE_CHARS, true);
  if (focusError) return focusError;

  const notesError = checkText(value.notes, "notes", MAX_NOTE_CHARS, false);
  if (notesError) return notesError;

  if (!Array.isArray(value.slots)) return fail("slots must be an array");
  if (value.slots.length < MIN_SLOTS) return fail("too few slots to be a workout");
  if (value.slots.length > MAX_SLOTS) return fail(`more than ${MAX_SLOTS} slots`);

  let totalSets = 0;
  for (let i = 0; i < value.slots.length; i++) {
    const slotError = validateSlot(value.slots[i], i);
    if (slotError) return slotError;
    totalSets += (value.slots[i] as Record<string, unknown>).sets as number;
  }

  // A three-hour session is a plausible-looking response and an unusable
  // workout. The per-slot cap alone doesn't catch ten slots of six sets.
  if (totalSets > MAX_TOTAL_SETS) {
    return fail(`${totalSets} sets is more than a session can hold`);
  }

  return urlCheck(value);
}

export function validatePlanBlueprint(value: unknown): ValidationResult {
  if (!isRecord(value)) return fail("not an object");

  const nameError = checkText(value.name, "name", MAX_NAME_CHARS, true);
  if (nameError) return nameError;

  const progressionError = checkText(value.progression, "progression", MAX_NOTE_CHARS, false);
  if (progressionError) return progressionError;

  const weeksError = checkInt(value.weeks, "weeks", 1, MAX_PLAN_WEEKS);
  if (weeksError) return weeksError;

  if (!Array.isArray(value.sessions)) return fail("sessions must be an array");
  if (value.sessions.length === 0) return fail("a plan needs at least one session");
  if (value.sessions.length > MAX_PLAN_SESSIONS) {
    return fail(`more than ${MAX_PLAN_SESSIONS} sessions`);
  }

  const keys = new Set<string>();
  for (const session of value.sessions) {
    if (!isRecord(session)) return fail("session is not an object");
    const keyError = checkText(session.key, "session key", MAX_NAME_CHARS, true);
    if (keyError) return keyError;
    if (keys.has(session.key as string)) {
      return fail(`two sessions share the key ${String(session.key)}`);
    }
    keys.add(session.key as string);

    const blueprintResult = validateWorkoutBlueprint(session.blueprint);
    if (!blueprintResult.ok) {
      return fail(`session ${String(session.key)}: ${blueprintResult.reason}`);
    }
  }

  if (!Array.isArray(value.weekdays)) return fail("weekdays must be an array");
  if (value.weekdays.length > 7) return fail("more than seven weekdays");

  const seenWeekdays = new Set<number>();
  for (const day of value.weekdays) {
    if (!isRecord(day)) return fail("weekday is not an object");
    const weekdayError = checkInt(day.weekday, "weekday", 1, 7);
    if (weekdayError) return weekdayError;
    if (seenWeekdays.has(day.weekday as number)) {
      return fail(`weekday ${String(day.weekday)} appears twice`);
    }
    seenWeekdays.add(day.weekday as number);

    // Referential integrity the server genuinely *can* check, unlike a task id:
    // both sides of this reference are in the response itself.
    if (day.sessionKey !== undefined && day.sessionKey !== null) {
      if (typeof day.sessionKey !== "string" || !keys.has(day.sessionKey)) {
        return fail(`weekday ${String(day.weekday)} names a session that doesn't exist`);
      }
    }
  }

  if (seenWeekdays.size === 0) return fail("the plan schedules nothing");

  return urlCheck(value);
}

/**
 * A URL in the output is a prompt-injection signature, not a feature.
 *
 * Same reasoning as `validateRecommendation`: the app never opens links from a
 * model response, so anything containing one is rejected outright rather than
 * sanitised and shown.
 */
function urlCheck(value: unknown): ValidationResult {
  if (/https?:\/\//i.test(JSON.stringify(value))) {
    return fail("response contained a URL");
  }
  return { ok: true };
}
