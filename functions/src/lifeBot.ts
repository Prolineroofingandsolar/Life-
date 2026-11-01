import { createHash, randomBytes } from "crypto";
import { getFirestore, FieldValue, Timestamp } from "firebase-admin/firestore";
import { onCall, onRequest, HttpsError, CallableRequest } from "firebase-functions/v2/https";
import type { Request } from "firebase-functions/v2/https";

/**
 * A way in for Grok Bot (x.ai/bot), or any agent that works by using websites.
 *
 * Grok Bot can't open an iPhone app, so Life gives it a private web page
 * instead. The person creates a secret link in the app and hands it to Grok
 * Bot once. Behind that link is a plain page: what's in Life, and simple forms
 * to add a workout, a task, water and so on.
 *
 * Nothing here edits the person's data directly. The app's data is one JSON
 * snapshot that the phone owns and uploads, and a server write into it would
 * race the phone's next upload. So every request lands in an inbox
 * (`users/{uid}/botInbox`), and the app carries it out the next time it's
 * open, through the same checked code paths the coach uses. The page shows
 * each request's status, so the bot can see what's been done.
 *
 * The link is the only credential. Only its SHA-256 is stored, it can be
 * replaced or switched off from the app at any time, and what it allows is a
 * closed list of changes: adding, editing and deleting tasks, routines,
 * planned workouts and weights, and logging habits, water, meals and
 * supplements. It can't touch completed workout history, money or settings.
 */

const REGION = "europe-west2";
const TOKENS = "lifeBotTokens";
const MAX_PENDING = 50;
const MAX_HISTORY = 25;
const MAX_EXERCISES_PER_WORKOUT = 15;

type Kind =
  | "createWorkout"
  | "planWorkout"
  | "addTask"
  | "completeTask"
  | "logHabit"
  | "logWater"
  | "logMeal"
  | "logWeight"
  | "logSupplement"
  | "updateTask"
  | "deleteTask"
  | "updateRoutine"
  | "deleteRoutine"
  | "deletePlannedWorkout"
  | "updateWeight"
  | "deleteWeight";

const KINDS: ReadonlySet<string> = new Set<Kind>([
  "createWorkout", "planWorkout", "addTask", "completeTask", "logHabit",
  "logWater", "logMeal", "logWeight", "logSupplement", "updateTask",
  "deleteTask", "updateRoutine", "deleteRoutine", "deletePlannedWorkout",
  "updateWeight", "deleteWeight",
]);

function hashToken(token: string): string {
  return createHash("sha256").update(token).digest("hex");
}

function pageURL(token: string): string {
  return `https://${REGION}-${process.env.GCLOUD_PROJECT ?? "life-1812f"}.cloudfunctions.net/lifeBot?key=${token}`;
}

// MARK: - Reading the person's data

interface LoggedSet {
  weight?: number; reps?: number; durationSec?: number; distanceKm?: number;
  isWarmup?: boolean; isDropSet?: boolean; isFailure?: boolean; done?: boolean; rpe?: number | null;
}

interface Snapshot {
  tasks?: Array<{ id: string; title: string; listId?: string; done?: boolean; dueDate?: string | null; notes?: string; dueDateOverride?: string | null }>;
  taskLists?: Array<{ id: string; name: string }>;
  habits?: Array<{ id: string; name: string; isArchived?: boolean; targetCount?: number; cadence?: string; targetUnit?: string; logs?: Array<{ dayKey: string; count?: number; slipped?: boolean }> }>;
  supplements?: Array<{ id: string; name: string; isArchived?: boolean; logs?: Array<{ date?: string; dayKey?: string }> }>;
  exercises?: Array<{ id: string; name: string; muscle?: string; equipment?: string }>;
  routines?: Array<{ id: string; name: string; exercises?: Array<{ exerciseId: string; defaultSets?: number; defaultReps?: number; repRangeMin?: number; repRangeMax?: number; restSeconds?: number }> }>;
  sessions?: Array<{ id?: string; name: string; startedAt?: string; finishedAt?: string; rating?: number | null; notes?: string; exercises?: Array<{ exerciseId: string; sets?: LoggedSet[] }> }>;
  plannedSessions?: Array<{ id?: string; date?: string; routineId?: string | null; routineName?: string; completed?: boolean }>;
  weightEntries?: Array<{ id?: string; date?: string; valueKg?: number }>;
  careDays?: Record<string, { dayKey?: string; waterGlasses?: number; meals?: string[]; steps?: number }>;
}

async function readSnapshot(uid: string): Promise<Snapshot> {
  const doc = await getFirestore()
    .collection("users").doc(uid)
    .collection("state").doc("snapshot")
    .get();
  const json = doc.get("json");
  if (typeof json !== "string") return {};
  try {
    return JSON.parse(json) as Snapshot;
  } catch {
    return {};
  }
}

/**
 * Meals are stored as one line of text each, so calories and protein ride in
 * the name ("Chicken and rice · 650 kcal · 45 g protein"). That way they show
 * in the app as they are, survive sync untouched, and can be added up here.
 */
function mealNutrition(meal: string): { kcal: number; proteinG: number } {
  const kcal = meal.match(/(\d+(?:\.\d+)?)\s*kcal/i);
  const protein = meal.match(/(\d+(?:\.\d+)?)\s*g\s*protein/i);
  return { kcal: kcal ? Number(kcal[1]) : 0, proteinG: protein ? Number(protein[1]) : 0 };
}

function formatSet(set: LoggedSet): string {
  const tags = [set.isWarmup ? "warm-up" : "", set.isDropSet ? "drop" : "", set.isFailure ? "failure" : "",
    set.rpe ? `RPE ${set.rpe}` : ""].filter(Boolean);
  let core: string;
  if ((set.distanceKm ?? 0) > 0 || ((set.durationSec ?? 0) > 0 && !(set.reps ?? 0))) {
    const mins = Math.round((set.durationSec ?? 0) / 60);
    core = [(set.distanceKm ?? 0) > 0 ? `${set.distanceKm} km` : "", mins ? `${mins} min` : ""].filter(Boolean).join(" in ");
  } else {
    core = (set.weight ?? 0) > 0 ? `${set.weight} kg × ${set.reps ?? 0}` : `${set.reps ?? 0} reps`;
  }
  return tags.length ? `${core} (${tags.join(", ")})` : core;
}

function lastDays(n: number): string[] {
  // Day keys as the app writes them (yyyy-MM-dd, the phone's local day). The
  // server is in UTC, so the window is padded by a day each side and the keys
  // that actually exist decide what is shown.
  const out: string[] = [];
  for (let i = -1; i < n; i++) {
    out.push(new Date(Date.now() - i * 86_400_000).toISOString().slice(0, 10));
  }
  return out;
}

/** What the page shows, trimmed to what an agent needs to make decisions. */
function summarise(s: Snapshot) {
  const exerciseName = new Map((s.exercises ?? []).map((e) => [e.id, e.name]));
  const fourWeeksAgo = Date.now() - 28 * 24 * 60 * 60 * 1000;
  const today = new Date(); today.setUTCHours(0, 0, 0, 0);
  const yesterday = today.getTime() - 86_400_000;
  const days = lastDays(14);
  const careDays = s.careDays ?? {};

  return {
    taskLists: (s.taskLists ?? []).map((l) => ({ id: l.id, name: l.name })),
    openTasks: (s.tasks ?? []).filter((t) => !t.done).slice(0, 100)
      .map((t) => ({
        id: t.id, title: t.title, listId: t.listId ?? "personal", due: t.dueDate ?? null,
        dueDate: t.dueDateOverride ? t.dueDateOverride.slice(0, 10) : null,
        notes: (t.notes ?? "").slice(0, 200),
      })),
    habits: (s.habits ?? []).filter((h) => !h.isArchived).map((h) => {
      const byDay = new Map((h.logs ?? []).map((l) => [l.dayKey, l]));
      const window = byDay.has(days[0]) ? days.slice(0, 14) : days.slice(1, 15);
      const history = window.map((d) => ({ day: d, count: byDay.get(d)?.count ?? 0, slipped: byDay.get(d)?.slipped ?? false }));
      const target = h.targetCount ?? 1;
      return {
        id: h.id, name: h.name, target, unit: h.targetUnit ?? "", cadence: h.cadence ?? "daily",
        history,
        daysHitLast14: history.filter((x) => x.count >= target && !x.slipped).length,
      };
    }),
    supplements: (s.supplements ?? []).filter((x) => !x.isArchived).map((x) => ({ id: x.id, name: x.name })),
    routines: (s.routines ?? []).map((r) => ({
      id: r.id,
      name: r.name,
      exercises: (r.exercises ?? []).map((e) => {
        const reps = e.repRangeMin && e.repRangeMax && e.repRangeMin !== e.repRangeMax
          ? `${e.repRangeMin}-${e.repRangeMax}` : String(e.defaultReps ?? e.repRangeMax ?? 10);
        return `${exerciseName.get(e.exerciseId) ?? "?"}, ${e.defaultSets ?? 3}x${reps}, ${e.restSeconds ?? 90}s`;
      }),
    })),
    recentWorkouts: (s.sessions ?? [])
      .filter((w) => w.finishedAt && Date.parse(w.finishedAt) >= fourWeeksAgo)
      .sort((a, b) => Date.parse(b.finishedAt!) - Date.parse(a.finishedAt!))
      .slice(0, 20)
      .map((w) => ({
        name: w.name,
        date: (w.finishedAt ?? "").slice(0, 10),
        minutes: w.startedAt && w.finishedAt
          ? Math.round((Date.parse(w.finishedAt) - Date.parse(w.startedAt)) / 60000) : null,
        rating: w.rating ?? null,
        notes: (w.notes ?? "").slice(0, 200),
        exercises: (w.exercises ?? []).map((e) => ({
          name: exerciseName.get(e.exerciseId) ?? "?",
          sets: (e.sets ?? []).filter((x) => x.done !== false).map(formatSet),
        })),
      })),
    plannedWorkouts: (s.plannedSessions ?? [])
      .filter((p) => !p.completed && p.date && Date.parse(p.date) >= yesterday)
      .sort((a, b) => Date.parse(a.date!) - Date.parse(b.date!))
      .slice(0, 21)
      .map((p) => ({ id: p.id ?? "", date: (p.date ?? "").slice(0, 10), name: p.routineName ?? "" })),
    recentWeights: (s.weightEntries ?? [])
      .slice(-30)
      .reverse()
      .map((w) => ({ id: w.id ?? "", date: (w.date ?? "").slice(0, 10), kg: w.valueKg })),
    dailyLog: days
      .filter((d) => careDays[d])
      .slice(0, 14)
      .map((d) => {
        const meals = careDays[d].meals ?? [];
        const totals = meals.map(mealNutrition).reduce(
          (a, b) => ({ kcal: a.kcal + b.kcal, proteinG: a.proteinG + b.proteinG }), { kcal: 0, proteinG: 0 });
        return {
          day: d,
          waterGlasses: careDays[d].waterGlasses ?? 0,
          steps: careDays[d].steps ?? 0,
          meals,
          kcal: Math.round(totals.kcal),
          proteinG: Math.round(totals.proteinG),
        };
      }),
    exerciseLibrary: (s.exercises ?? [])
      .map((e) => ({ id: e.id, name: e.name, muscle: e.muscle ?? "", equipment: e.equipment ?? "" }))
      .sort((a, b) => a.muscle.localeCompare(b.muscle) || a.name.localeCompare(b.name)),
  };
}

type Summary = ReturnType<typeof summarise>;

// MARK: - Turning a submitted form into an inbox item

class BadRequest extends Error {}

function text(value: unknown, max: number): string {
  return String(value ?? "").replace(/\s+/g, " ").trim().slice(0, max);
}

function int(value: unknown, min: number, max: number, fallback: number): number {
  const n = Math.round(Number(value));
  if (!Number.isFinite(n)) return fallback;
  return Math.min(Math.max(n, min), max);
}

function requireId(value: unknown, known: Array<{ id: string; name: string }>, what: string): string {
  const raw = text(value, 200);
  const byId = known.find((k) => k.id === raw);
  if (byId) return byId.id;
  // Forgiving on names, because an agent reading a page will often type what
  // it sees rather than copy an id.
  const byName = known.filter((k) => k.name.toLowerCase() === raw.toLowerCase());
  if (byName.length === 1) return byName[0].id;
  throw new BadRequest(`I couldn't find that ${what} ("${raw}"). Use one of the ids listed on the page.`);
}

/**
 * One exercise per line: "Name or id, sets x reps, rest". Only the name is
 * required. Names must match the person's own library, which the page lists,
 * because a routine can only hold exercises the app knows.
 */
function parseExercises(lines: string, library: Summary["exerciseLibrary"]) {
  const rows = lines.split(/\r?\n/).map((l) => l.trim()).filter(Boolean);
  if (rows.length === 0) throw new BadRequest("Add at least one exercise, one per line.");
  if (rows.length > MAX_EXERCISES_PER_WORKOUT) {
    throw new BadRequest(`That's more than ${MAX_EXERCISES_PER_WORKOUT} exercises. Keep it to a normal session.`);
  }

  return rows.map((row) => {
    const [namePart, ...rest] = row.split(/[,|;]/).map((p) => p.trim());
    const name = namePart.replace(/^[-*\d.)\s]+/, "").trim();
    const lower = name.toLowerCase();
    const match =
      library.find((e) => e.id === name) ??
      library.find((e) => e.name.toLowerCase() === lower) ??
      (() => {
        const partial = library.filter((e) =>
          e.name.toLowerCase().includes(lower) || lower.includes(e.name.toLowerCase()));
        return partial.length === 1 ? partial[0] : undefined;
      })();
    if (!match) {
      const words = lower.split(/\s+/).filter((w) => w.length > 2);
      const close = library
        .filter((e) => words.some((w) => e.name.toLowerCase().includes(w)))
        .slice(0, 5)
        .map((e) => e.name);
      throw new BadRequest(
        `"${name}" isn't in the exercise library.` +
        (close.length ? ` Did you mean: ${close.join(", ")}?` : " Pick a name from the library on the page.")
      );
    }

    const detail = rest.join(" ");
    const setsReps = detail.match(/(\d+)\s*[x×]\s*(\d+)(?:\s*-\s*(\d+))?/i);
    const restMatch = detail.match(/(\d+)\s*(s|sec|secs|seconds|m|min|mins|minutes)\b/i);
    const sets = setsReps ? int(setsReps[1], 1, 10, 3) : 3;
    const repsLow = setsReps ? int(setsReps[2], 1, 100, 10) : 10;
    const repsHigh = setsReps && setsReps[3] ? int(setsReps[3], repsLow, 100, repsLow) : repsLow;
    let restSeconds = 90;
    if (restMatch) {
      const n = Number(restMatch[1]);
      restSeconds = int(/^m/i.test(restMatch[2]) ? n * 60 : n, 15, 600, 90);
    }
    return { exerciseId: match.id, name: match.name, sets, repsMin: repsLow, repsMax: repsHigh, restSeconds };
  });
}

function taskChoices(summary: Summary) {
  return summary.openTasks.map((t) => ({ id: t.id, name: t.title }));
}

function weightChoices(summary: Summary) {
  return summary.recentWeights.map((w) => ({ id: w.id, name: `${w.date} ${w.kg} kg` }));
}

function buildItem(kind: string, body: Record<string, unknown>, summary: Summary): Record<string, unknown> {
  if (!KINDS.has(kind)) throw new BadRequest("That isn't something this page can do.");

  switch (kind as Kind) {
    case "createWorkout": {
      const name = text(body.name, 60) || "Today's workout";
      const exercises = parseExercises(String(body.exercises ?? ""), summary.exerciseLibrary);
      const when = ["today", "tomorrow", "none"].includes(String(body.when)) ? String(body.when) : "today";
      return { kind, name, exercises, when, notes: text(body.notes, 300) };
    }
    case "planWorkout": {
      const routineId = requireId(body.routineId, summary.routines, "routine");
      const when = String(body.when) === "tomorrow" ? "tomorrow" : "today";
      return { kind, routineId, when };
    }
    case "addTask": {
      const title = text(body.title, 120);
      if (!title) throw new BadRequest("A task needs a title.");
      const due = ["today", "tomorrow", "thisWeek"].includes(String(body.due)) ? String(body.due) : "today";
      const listId = summary.taskLists.some((l) => l.id === body.listId) ? String(body.listId) : undefined;
      return { kind, title, due, ...(listId ? { listId } : {}) };
    }
    case "completeTask":
      return { kind, targetId: requireId(body.taskId, summary.openTasks.map((t) => ({ id: t.id, name: t.title })), "task") };
    case "logHabit":
      return { kind, targetId: requireId(body.habitId, summary.habits, "habit"), count: int(body.count, 1, 20, 1) };
    case "logWater":
      return { kind, count: int(body.glasses, 1, 8, 1) };
    case "logMeal": {
      const meal = text(body.meal, 60).replace(/·/g, "-");
      if (!meal) throw new BadRequest("Say what was eaten.");
      const kcal = body.kcal === undefined || body.kcal === "" ? 0 : int(body.kcal, 0, 5000, 0);
      const protein = body.proteinG === undefined || body.proteinG === "" ? 0 : int(body.proteinG, 0, 400, 0);
      const title = [meal, kcal ? `${kcal} kcal` : "", protein ? `${protein} g protein` : ""]
        .filter(Boolean).join(" · ");
      return { kind, title };
    }
    case "logWeight": {
      const kg = Number(body.kg);
      if (!Number.isFinite(kg) || kg < 25 || kg > 300) {
        throw new BadRequest("Weight must be in kilograms, between 25 and 300.");
      }
      return { kind, weightKg: Math.round(kg * 10) / 10 };
    }
    case "logSupplement":
      return { kind, targetId: requireId(body.supplementId, summary.supplements, "supplement") };

    case "updateTask": {
      const targetId = requireId(body.taskId, taskChoices(summary), "task");
      const changes: Record<string, unknown> = {};
      const title = text(body.title, 120);
      if (title) changes.title = title;
      if (["today", "tomorrow", "thisWeek"].includes(String(body.due))) changes.due = String(body.due);
      const date = text(body.dueDate, 10);
      if (date) {
        if (!/^\d{4}-\d{2}-\d{2}$/.test(date) || Number.isNaN(Date.parse(date))) {
          throw new BadRequest("dueDate must look like 2026-11-05.");
        }
        changes.dueDate = date;
      }
      if (summary.taskLists.some((l) => l.id === body.listId)) changes.listId = String(body.listId);
      if (typeof body.notes === "string" && body.notes.trim()) changes.notes = String(body.notes).trim().slice(0, 1000);
      if (Object.keys(changes).length === 0) throw new BadRequest("Say what to change: title, due, dueDate, listId or notes.");
      return { kind, targetId, ...changes };
    }
    case "deleteTask":
      return { kind, targetId: requireId(body.taskId, taskChoices(summary), "task") };

    case "updateRoutine": {
      const targetId = requireId(body.routineId, summary.routines, "routine");
      const name = text(body.name, 60);
      const lines = String(body.exercises ?? "").trim();
      if (!name && !lines) throw new BadRequest("Give a new name, new exercises, or both.");
      return {
        kind, targetId,
        ...(name ? { name } : {}),
        ...(lines ? { exercises: parseExercises(lines, summary.exerciseLibrary) } : {}),
      };
    }
    case "deleteRoutine":
      return { kind, targetId: requireId(body.routineId, summary.routines, "routine") };

    case "deletePlannedWorkout": {
      const plans = summary.plannedWorkouts.map((p) => ({ id: p.id, name: `${p.date} ${p.name}` }));
      return { kind, targetId: requireId(body.planId, plans, "planned workout") };
    }

    case "updateWeight": {
      const targetId = requireId(body.weightId, weightChoices(summary), "weight entry");
      const kg = Number(body.kg);
      if (!Number.isFinite(kg) || kg < 25 || kg > 300) {
        throw new BadRequest("Weight must be in kilograms, between 25 and 300.");
      }
      return { kind, targetId, weightKg: Math.round(kg * 10) / 10 };
    }
    case "deleteWeight":
      return { kind, targetId: requireId(body.weightId, weightChoices(summary), "weight entry") };
  }
}

async function enqueue(uid: string, item: Record<string, unknown>): Promise<string> {
  const inbox = getFirestore().collection("users").doc(uid).collection("botInbox");
  const pending = await inbox.where("status", "==", "pending").count().get();
  if (pending.data().count >= MAX_PENDING) {
    throw new BadRequest(
      `There are already ${MAX_PENDING} requests waiting for the app. Open Life on the phone so it can catch up.`
    );
  }
  const ref = await inbox.add({
    ...item,
    status: "pending",
    source: "grokBot",
    createdAt: FieldValue.serverTimestamp(),
  });
  return ref.id;
}

async function history(uid: string) {
  const snap = await getFirestore()
    .collection("users").doc(uid).collection("botInbox")
    .orderBy("createdAt", "desc")
    .limit(MAX_HISTORY)
    .get();
  return snap.docs.map((d) => {
    const data = d.data();
    const created = data.createdAt instanceof Timestamp ? data.createdAt.toDate().toISOString() : null;
    return {
      id: d.id,
      kind: String(data.kind ?? ""),
      what: describe(data),
      status: String(data.status ?? "pending"),
      result: typeof data.result === "string" ? data.result : null,
      createdAt: created,
    };
  });
}

function describe(d: Record<string, unknown>): string {
  switch (d.kind) {
    case "createWorkout": return `New workout "${d.name}" (${(d.exercises as unknown[] | undefined)?.length ?? 0} exercises, ${d.when})`;
    case "planWorkout": return `Plan routine for ${d.when}`;
    case "addTask": return `Add task "${d.title}"`;
    case "completeTask": return "Complete a task";
    case "logHabit": return "Log a habit";
    case "logWater": return `Log ${d.count} glass(es) of water`;
    case "logMeal": return `Log meal "${d.title}"`;
    case "logWeight": return `Log weight ${d.weightKg} kg`;
    case "logSupplement": return "Log a supplement";
    case "updateTask": return `Edit a task${d.title ? ` to "${d.title}"` : ""}`;
    case "deleteTask": return "Delete a task";
    case "updateRoutine": return `Edit a routine${d.name ? ` ("${d.name}")` : ""}`;
    case "deleteRoutine": return "Delete a routine";
    case "deletePlannedWorkout": return "Remove a planned workout";
    case "updateWeight": return `Correct a weight to ${d.weightKg} kg`;
    case "deleteWeight": return "Delete a weight entry";
    default: return String(d.kind ?? "");
  }
}

// MARK: - The page

function esc(value: unknown): string {
  return String(value ?? "").replace(/[&<>"']/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", "\"": "&quot;", "'": "&#39;" }[c]!));
}

function options(items: Array<{ id: string; name: string }>): string {
  return items.map((i) => `<option value="${esc(i.id)}">${esc(i.name)}</option>`).join("");
}

function renderPage(
  token: string,
  summary: Summary,
  recent: Awaited<ReturnType<typeof history>>,
  notice?: { ok: boolean; text: string }
): string {
  const k = `<input type="hidden" name="key" value="${esc(token)}">`;
  const form = (kind: string, title: string, fields: string, button: string, danger = false) => `
<section class="card" id="${kind}">
  <h3>${title}</h3>
  <form method="post" action="/lifeBot/do?key=${esc(token)}">
    ${k}<input type="hidden" name="kind" value="${kind}">
    ${fields}
    <button type="submit"${danger ? " class=danger" : ""}>${button}</button>
  </form>
</section>`;

  const list = (rows: string[]) => rows.length ? `<ul>${rows.join("")}</ul>` : "<p class=muted>None.</p>";
  const libraryByMuscle = new Map<string, Summary["exerciseLibrary"]>();
  for (const e of summary.exerciseLibrary) {
    libraryByMuscle.set(e.muscle, [...(libraryByMuscle.get(e.muscle) ?? []), e]);
  }
  const taskOptions = options(summary.openTasks.map((t) => ({ id: t.id, name: t.title })));
  const routineOptions = options(summary.routines);
  const weightOptions = options(weightChoices(summary));
  const planOptions = options(summary.plannedWorkouts.map((p) => ({ id: p.id, name: `${p.date}: ${p.name}` })));
  const dueSelect = (id: string, blank: boolean) => `<select id="${id}" name="due">${blank ? "<option value=\"\">Leave as it is</option>" : ""}<option value="today">Today</option><option value="tomorrow">Tomorrow</option><option value="thisWeek">This week</option></select>`;
  const statusText = (s: string) =>
    s === "pending" ? "Waiting for the app" : s === "done" ? "Done" : s === "claimed" ? "Being applied" : "Couldn't be done";

  return `<!doctype html>
<html lang="en-GB"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow">
<title>Life for Grok Bot</title>
<style>
:root{color-scheme:light dark;--bg:#f6f7f8;--card:#fff;--text:#16181a;--muted:#5d646b;--line:#dde1e5;--accent:#0f8f83;--danger:#b42318;--ok:#e3f6ee;--bad:#fde8e8}
@media (prefers-color-scheme:dark){:root{--bg:#111315;--card:#1b1e21;--text:#eceef0;--muted:#9aa3ab;--line:#2c3136;--ok:#12332a;--bad:#3a1717}}
body{margin:0;background:var(--bg);color:var(--text);font:16px/1.45 -apple-system,system-ui,sans-serif}
main{max-width:900px;margin:0 auto;padding:16px}
h1{font-size:24px;margin:8px 0}h2{font-size:19px;margin:28px 0 8px}h3{font-size:16px;margin:0 0 10px}
.card{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:14px;margin:10px 0}
label{display:block;margin:8px 0 4px;font-weight:600;font-size:14px}
input,select,textarea{width:100%;box-sizing:border-box;font:inherit;padding:8px;border:1px solid var(--line);border-radius:6px;background:var(--bg);color:var(--text)}
textarea{min-height:150px}
button{margin-top:12px;font:inherit;font-weight:600;padding:9px 16px;border:0;border-radius:6px;background:var(--accent);color:#fff;cursor:pointer}
button.danger{background:var(--danger)}
.muted{color:var(--muted)}.notice{padding:12px;border-radius:8px;margin:12px 0}.ok{background:var(--ok)}.bad{background:var(--bad)}
code{font-size:13px}table{border-collapse:collapse;width:100%;font-size:14px}td,th{border-bottom:1px solid var(--line);padding:5px;text-align:left;vertical-align:top}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(260px,1fr));gap:10px}
ul{padding-left:20px;margin:0}li{margin:4px 0}
</style></head><body><main>
<h1>Life for Grok Bot</h1>
<p class="muted">This private page lets an assistant read and change Will's Life app. Every change goes to the app, which carries it out when Life is open on the phone (usually within a minute of opening it) and reports back. Each request's outcome is listed under "Recent requests", and also at <code>/lifeBot/api/requests</code>.</p>
${notice ? `<div class="notice ${notice.ok ? "ok" : "bad"}" role="status">${esc(notice.text)}</div>` : ""}

<h2>Recent requests</h2>
<div class="card">${recent.length ? `<table><tr><th>When (UTC)</th><th>Request</th><th>Status</th></tr>${recent.map((r) =>
  `<tr><td>${esc((r.createdAt ?? "").replace("T", " ").slice(0, 16))}</td><td>${esc(r.what)}${r.result ? `<br><span class="muted">${esc(r.result)}</span>` : ""}</td><td>${esc(statusText(r.status))}</td></tr>`).join("")}</table>` : "<p class=muted>Nothing yet.</p>"}</div>

<h2>Workouts and routines</h2>
${form("createWorkout", "Create a workout or save a routine", `
  <label for="w-name">Name</label>
  <input id="w-name" name="name" placeholder="e.g. Upper A, or Push day 3 November" maxlength="60">
  <label for="w-ex">Exercises, one per line: name, sets x reps, rest</label>
  <textarea id="w-ex" name="exercises" placeholder="Bench Press, 4x6-8, 2 min&#10;Incline Dumbbell Press, 3x10, 90s&#10;Cable Fly, 3x12-15, 60s"></textarea>
  <p class="muted">Use exercise names exactly as in the exercise library below. Sets, reps and rest are optional (defaults: 3 x 10, 90s). It is saved as a routine that stays in the app. For a programme, save each day as its own routine.</p>
  <label for="w-when">Put it in the plan for</label>
  <select id="w-when" name="when"><option value="today">Today</option><option value="tomorrow">Tomorrow</option><option value="none">Don't plan it, just save the routine</option></select>
  <label for="w-notes">Notes (optional)</label>
  <input id="w-notes" name="notes" maxlength="300">`, "Save")}

<div class="grid">
${summary.routines.length ? form("planWorkout", "Plan a routine", `
  <label for="p-r">Routine</label><select id="p-r" name="routineId">${routineOptions}</select>
  <label for="p-w">When</label><select id="p-w" name="when"><option value="today">Today</option><option value="tomorrow">Tomorrow</option></select>`, "Plan it") : ""}
${summary.routines.length ? form("updateRoutine", "Edit a routine", `
  <label for="ur-r">Routine</label><select id="ur-r" name="routineId">${routineOptions}</select>
  <label for="ur-n">New name (optional)</label><input id="ur-n" name="name" maxlength="60">
  <label for="ur-e">Replace exercises with (optional, same format as above)</label><textarea id="ur-e" name="exercises"></textarea>`, "Save changes") : ""}
${summary.routines.length ? form("deleteRoutine", "Delete a routine", `
  <label for="dr-r">Routine</label><select id="dr-r" name="routineId">${routineOptions}</select>
  <p class="muted">Past workouts done from it are kept.</p>`, "Delete routine", true) : ""}
${summary.plannedWorkouts.length ? form("deletePlannedWorkout", "Remove a planned workout", `
  <label for="dp-p">Planned workout</label><select id="dp-p" name="planId">${planOptions}</select>`, "Remove", true) : ""}
</div>

<h2>Tasks</h2>
<div class="grid">
${form("addTask", "Add a task", `
  <label for="t-t">Task</label><input id="t-t" name="title" maxlength="120" required>
  <label for="t-l">List</label><select id="t-l" name="listId">${options(summary.taskLists)}</select>
  <label for="t-d">Due</label>${dueSelect("t-d", false)}`, "Add task")}
${summary.openTasks.length ? form("updateTask", "Edit a task", `
  <label for="ut-t">Task</label><select id="ut-t" name="taskId">${taskOptions}</select>
  <label for="ut-n">New title (optional)</label><input id="ut-n" name="title" maxlength="120">
  <label for="ut-d">Due</label>${dueSelect("ut-d", true)}
  <label for="ut-date">Or an exact due date (optional)</label><input id="ut-date" name="dueDate" type="date">
  <label for="ut-l">Move to list</label><select id="ut-l" name="listId"><option value="">Leave as it is</option>${options(summary.taskLists)}</select>
  <label for="ut-notes">Notes (optional, replaces existing)</label><input id="ut-notes" name="notes" maxlength="1000">`, "Save changes") : ""}
${summary.openTasks.length ? form("completeTask", "Tick off a task", `
  <label for="c-t">Task</label><select id="c-t" name="taskId">${taskOptions}</select>`, "Mark done") : ""}
${summary.openTasks.length ? form("deleteTask", "Delete a task", `
  <label for="dt-t">Task</label><select id="dt-t" name="taskId">${taskOptions}</select>`, "Delete task", true) : ""}
</div>

<h2>Logging</h2>
<div class="grid">
${summary.habits.length ? form("logHabit", "Log a habit", `
  <label for="h-h">Habit</label><select id="h-h" name="habitId">${options(summary.habits)}</select>
  <label for="h-c">Times</label><input id="h-c" name="count" type="number" min="1" max="20" value="1">`, "Log habit") : ""}
${form("logWater", "Log water", `
  <label for="wa">Glasses</label><input id="wa" name="glasses" type="number" min="1" max="8" value="1">`, "Log water")}
${form("logMeal", "Log a meal", `
  <label for="m">What was eaten</label><input id="m" name="meal" maxlength="60" required>
  <label for="m-k">Calories (kcal, optional)</label><input id="m-k" name="kcal" type="number" min="0" max="5000">
  <label for="m-p">Protein (grams, optional)</label><input id="m-p" name="proteinG" type="number" min="0" max="400">`, "Log meal")}
${summary.supplements.length ? form("logSupplement", "Log a supplement", `
  <label for="s">Supplement</label><select id="s" name="supplementId">${options(summary.supplements)}</select>`, "Log it") : ""}
${form("logWeight", "Log weight", `
  <label for="kg">Kilograms</label><input id="kg" name="kg" type="number" step="0.1" min="25" max="300" required>`, "Log weight")}
${summary.recentWeights.length ? form("updateWeight", "Correct a weight", `
  <label for="uw-w">Entry</label><select id="uw-w" name="weightId">${weightOptions}</select>
  <label for="uw-kg">Correct kilograms</label><input id="uw-kg" name="kg" type="number" step="0.1" min="25" max="300" required>`, "Correct it") : ""}
${summary.recentWeights.length ? form("deleteWeight", "Delete a weight", `
  <label for="dw-w">Entry</label><select id="dw-w" name="weightId">${weightOptions}</select>`, "Delete weight", true) : ""}
</div>

<h2>What's in Life</h2>
<section class="card"><h3>Workouts, last 4 weeks (every set: kg × reps)</h3>${list(summary.recentWorkouts.map((w) =>
  `<li><b>${esc(w.date)}</b> ${esc(w.name)}${w.minutes ? ` <span class="muted">(${esc(w.minutes)} min${w.rating ? `, rated ${esc(w.rating)}/5` : ""})</span>` : ""}<ul>${w.exercises.map((e) =>
    `<li>${esc(e.name)}: ${esc(e.sets.join(", ") || "no sets logged")}</li>`).join("")}</ul></li>`))}</section>
<div class="grid">
<section class="card"><h3>Planned workouts</h3>${list(summary.plannedWorkouts.map((p) => `<li><b>${esc(p.date)}</b> ${esc(p.name)}</li>`))}</section>
<section class="card"><h3>Routines</h3>${list(summary.routines.map((r) => `<li><b>${esc(r.name)}</b><br><span class="muted">${esc(r.exercises.join("; "))}</span></li>`))}</section>
<section class="card"><h3>Open tasks</h3>${list(summary.openTasks.map((t) => `<li>${esc(t.title)} <span class="muted">(${esc(t.listId)}${t.dueDate ? `, due ${esc(t.dueDate)}` : t.due ? `, ${esc(t.due)}` : ""})</span></li>`))}</section>
<section class="card"><h3>Weights (newest first)</h3>${list(summary.recentWeights.slice(0, 15).map((w) => `<li>${esc(w.date)}: ${esc(w.kg)} kg</li>`))}</section>
</div>
<section class="card"><h3>Habits, last 14 days</h3>${summary.habits.length ? `<table><tr><th>Habit</th><th>Days hit</th><th>Each day, newest first</th></tr>${summary.habits.map((h) =>
  `<tr><td>${esc(h.name)} <span class="muted">(target ${esc(h.target)}${h.unit ? ` ${esc(h.unit)}` : ""}, ${esc(h.cadence)})</span></td><td>${esc(h.daysHitLast14)} of 14</td><td>${esc(h.history.map((x) => `${x.day.slice(5)}: ${x.slipped ? "slipped" : x.count}`).join(", "))}</td></tr>`).join("")}</table>` : "<p class=muted>No habits.</p>"}</section>
<section class="card"><h3>Water, meals and steps, last 14 days</h3>${summary.dailyLog.length ? `<table><tr><th>Day</th><th>Water</th><th>Calories / protein</th><th>Meals</th><th>Steps</th></tr>${summary.dailyLog.map((d) =>
  `<tr><td>${esc(d.day)}</td><td>${esc(d.waterGlasses)} glasses</td><td>${d.kcal || d.proteinG ? `${esc(d.kcal)} kcal, ${esc(d.proteinG)} g` : "<span class=muted>not given</span>"}</td><td>${esc(d.meals.join("; "))}</td><td>${esc(d.steps)}</td></tr>`).join("")}</table>` : "<p class=muted>Nothing logged.</p>"}</section>

<h2>Exercise library</h2>
<div class="card">${summary.exerciseLibrary.length ? [...libraryByMuscle.entries()].map(([muscle, items]) =>
  `<p><b>${esc(muscle || "Other")}</b>: ${items.map((e) => `${esc(e.name)} <span class="muted">(${esc(e.equipment)})</span>`).join(", ")}</p>`).join("") : "<p class=muted>The app hasn't synced its library yet.</p>"}</div>

<h2>For agents</h2>
<div class="card muted">
<p>JSON API, same abilities as the forms. Send the key in an <code>X-Life-Key</code> header (or <code>Authorization: Bearer …</code>) rather than in the address where you can.</p>
<ul>
<li><code>GET /lifeBot/api/state</code>: everything above, as JSON.</li>
<li><code>GET /lifeBot/api/requests</code>: recent requests and what the app did with each.</li>
<li><code>POST /lifeBot/api/do</code> with a JSON body: <code>kind</code> plus the form's fields, e.g. <code>{"kind":"createWorkout","name":"Legs","exercises":"Squat, 5x5, 3 min\\nLeg Press, 3x10","when":"today"}</code>. Kinds: createWorkout, planWorkout, updateRoutine, deleteRoutine, deletePlannedWorkout, addTask, updateTask, completeTask, deleteTask, logHabit, logWater, logMeal (meal, kcal, proteinG), logSupplement, logWeight, updateWeight, deleteWeight. Ids are in <code>/api/state</code>.</li>
</ul>
</div>
</main></body></html>`;
}

// MARK: - HTTP endpoint (what Grok Bot opens)

async function uidForToken(token: string): Promise<string | null> {
  if (!/^[A-Za-z0-9_-]{20,100}$/.test(token)) return null;
  const doc = await getFirestore().collection(TOKENS).doc(hashToken(token)).get();
  const uid = doc.get("uid");
  return typeof uid === "string" ? uid : null;
}

function tokenFrom(req: Request): string {
  // A header is preferred: it stays out of browser history and server logs.
  // The key in the address is there for agents that can only open a page.
  const custom = req.get("x-life-key");
  if (custom) return custom.trim();
  const header = req.get("authorization") ?? "";
  if (header.toLowerCase().startsWith("bearer ")) return header.slice(7).trim();
  const fromQuery = typeof req.query.key === "string" ? req.query.key : "";
  const fromBody = typeof req.body?.key === "string" ? req.body.key : "";
  return (fromQuery || fromBody).trim();
}

export const lifeBot = onRequest(
  { region: REGION, memory: "256MiB", maxInstances: 3, timeoutSeconds: 30, invoker: "public" },
  async (req, res) => {
    res.set("Cache-Control", "no-store");
    res.set("X-Robots-Tag", "noindex");
    res.set("Referrer-Policy", "no-referrer");

    const token = tokenFrom(req);
    const uid = token ? await uidForToken(token) : null;
    const path = req.path.replace(/\/+$/, "") || "/";
    const isApi = path.startsWith("/api");

    if (!uid) {
      if (isApi) {
        res.status(401).json({ ok: false, error: "This link isn't valid. Make a new one in Life: Settings, Grok Bot." });
      } else {
        res.status(401).type("html").send("<!doctype html><meta charset=utf-8><title>Life</title><p style=\"font-family:system-ui;padding:16px\">This link isn't valid any more. Make a new one in the Life app under Settings, Grok Bot.</p>");
      }
      return;
    }

    try {
      await getFirestore().collection(TOKENS).doc(hashToken(token))
        .set({ lastUsedAt: FieldValue.serverTimestamp() }, { merge: true });

      if (req.method === "GET" && path === "/api/state") {
        const [summary, recent] = await Promise.all([readSnapshot(uid).then(summarise), history(uid)]);
        res.json({ ok: true, ...summary, recentRequests: recent });
        return;
      }

      if (req.method === "GET" && path === "/api/requests") {
        res.json({ ok: true, requests: await history(uid) });
        return;
      }

      if (req.method === "POST" && (path === "/do" || path === "/api/do")) {
        const body = (req.body ?? {}) as Record<string, unknown>;
        const summary = summarise(await readSnapshot(uid));
        let notice: { ok: boolean; text: string };
        try {
          const item = buildItem(String(body.kind ?? ""), body, summary);
          const id = await enqueue(uid, item);
          notice = { ok: true, text: `Sent to Life: ${describe(item)}. It will be done the next time the app is open.` };
          if (isApi) {
            res.json({ ok: true, id, message: notice.text });
            return;
          }
        } catch (error) {
          if (!(error instanceof BadRequest)) throw error;
          if (isApi) {
            res.status(400).json({ ok: false, error: error.message });
            return;
          }
          notice = { ok: false, text: error.message };
        }
        res.status(notice.ok ? 200 : 400).type("html").send(renderPage(token, summary, await history(uid), notice));
        return;
      }

      if (req.method === "GET" && path === "/") {
        const [summary, recent] = await Promise.all([readSnapshot(uid).then(summarise), history(uid)]);
        res.type("html").send(renderPage(token, summary, recent));
        return;
      }

      res.status(404).json({ ok: false, error: "Not found." });
    } catch (error) {
      console.error("[lifeBot]", error instanceof Error ? `${error.name}: ${error.message}` : typeof error);
      res.status(500).json({ ok: false, error: "Something went wrong. Try again in a minute." });
    }
  }
);

// MARK: - Callable for the app

interface AppRequest {
  action: "status" | "createLink" | "revokeLink" | "claim" | "complete";
  results?: Array<{ id: string; ok: boolean; message?: string }>;
}

/**
 * Everything the app does with Grok Bot: make or switch off the link, and
 * collect and report on what Grok Bot asked for.
 */
export const lifeBotApp = onCall(
  { region: REGION, memory: "256MiB", maxInstances: 3 },
  async (request: CallableRequest<AppRequest>) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Sign in first.");
    const db = getFirestore();
    const linkRef = db.collection("users").doc(uid).collection("lifeBot").doc("link");
    const inbox = db.collection("users").doc(uid).collection("botInbox");

    switch (request.data?.action) {
      case "status": {
        const link = await linkRef.get();
        return { connected: link.exists, createdAt: link.get("createdAt")?.toDate?.()?.toISOString() ?? null };
      }

      case "createLink": {
        // One link at a time: making a new one switches the old one off.
        const old = await linkRef.get();
        const token = randomBytes(24).toString("base64url");
        const batch = db.batch();
        const oldHash = old.get("tokenHash");
        if (typeof oldHash === "string") batch.delete(db.collection(TOKENS).doc(oldHash));
        batch.set(db.collection(TOKENS).doc(hashToken(token)), { uid, createdAt: FieldValue.serverTimestamp() });
        batch.set(linkRef, { tokenHash: hashToken(token), createdAt: FieldValue.serverTimestamp() });
        await batch.commit();
        return { url: pageURL(token) };
      }

      case "revokeLink": {
        const old = await linkRef.get();
        const batch = db.batch();
        const oldHash = old.get("tokenHash");
        if (typeof oldHash === "string") batch.delete(db.collection(TOKENS).doc(oldHash));
        batch.delete(linkRef);
        await batch.commit();
        return { connected: false };
      }

      case "claim": {
        // Claimed in a transaction so two devices open at once can't both
        // carry out the same request. A claim older than ten minutes is
        // treated as abandoned (the app was closed mid-way) and offered again.
        // No orderBy: combined with the filter it would need a composite
        // index, which is one more manual step. Sorted here instead.
        const found = await inbox.where("status", "in", ["pending", "claimed"]).limit(50).get();
        const pending = {
          docs: [...found.docs].sort((a, b) =>
            (a.get("createdAt")?.toMillis?.() ?? 0) - (b.get("createdAt")?.toMillis?.() ?? 0)).slice(0, 20),
        };
        const staleBefore = Date.now() - 10 * 60 * 1000;
        const claimed: Array<Record<string, unknown>> = [];
        for (const doc of pending.docs) {
          const ok = await db.runTransaction(async (tx) => {
            const fresh = await tx.get(doc.ref);
            const status = fresh.get("status");
            const claimedAt: Timestamp | undefined = fresh.get("claimedAt");
            if (status === "pending" || (status === "claimed" && (claimedAt?.toMillis() ?? 0) < staleBefore)) {
              tx.update(doc.ref, { status: "claimed", claimedAt: FieldValue.serverTimestamp() });
              return true;
            }
            return false;
          });
          if (!ok) continue;
          const data = doc.data();
          const created = data.createdAt instanceof Timestamp ? data.createdAt.toDate().toISOString() : new Date().toISOString();
          const rest: Record<string, unknown> = { ...data };
          delete rest.status; delete rest.claimedAt; delete rest.createdAt;
          claimed.push({ ...rest, id: doc.id, createdAt: created });
        }
        return { items: claimed };
      }

      case "complete": {
        const results = (request.data.results ?? []).slice(0, 20);
        const batch = db.batch();
        for (const r of results) {
          if (typeof r?.id !== "string" || !/^[A-Za-z0-9]{1,64}$/.test(r.id)) continue;
          batch.update(inbox.doc(r.id), {
            status: r.ok ? "done" : "failed",
            result: text(r.message, 200),
            doneAt: FieldValue.serverTimestamp(),
          });
        }
        await batch.commit();
        return { ok: true };
      }

      default:
        throw new HttpsError("invalid-argument", "Unknown action.");
    }
  }
);
