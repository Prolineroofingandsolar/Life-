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
 * short closed list of small, easy-to-undo changes. It can't delete anything.
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
  | "logSupplement";

const KINDS: ReadonlySet<string> = new Set<Kind>([
  "createWorkout", "planWorkout", "addTask", "completeTask", "logHabit",
  "logWater", "logMeal", "logWeight", "logSupplement",
]);

function hashToken(token: string): string {
  return createHash("sha256").update(token).digest("hex");
}

function pageURL(token: string): string {
  return `https://${REGION}-${process.env.GCLOUD_PROJECT ?? "life-1812f"}.cloudfunctions.net/lifeBot?key=${token}`;
}

// MARK: - Reading the person's data

interface Snapshot {
  tasks?: Array<{ id: string; title: string; listId?: string; done?: boolean; dueDate?: string }>;
  taskLists?: Array<{ id: string; name: string }>;
  habits?: Array<{ id: string; name: string; isArchived?: boolean }>;
  supplements?: Array<{ id: string; name: string; isArchived?: boolean }>;
  exercises?: Array<{ id: string; name: string; muscle?: string; equipment?: string }>;
  routines?: Array<{ id: string; name: string; exercises?: Array<{ exerciseId: string; defaultSets?: number; defaultReps?: number }> }>;
  sessions?: Array<{ name: string; startedAt?: string; finishedAt?: string; exercises?: Array<{ exerciseId: string; sets?: unknown[] }> }>;
  plannedSessions?: Array<{ date?: string; routineName?: string; completed?: boolean }>;
  weightEntries?: Array<{ date?: string; valueKg?: number }>;
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

/** What the page shows, trimmed to what an agent needs to make decisions. */
function summarise(s: Snapshot) {
  const exerciseName = new Map((s.exercises ?? []).map((e) => [e.id, e.name]));
  const twoWeeksAgo = Date.now() - 14 * 24 * 60 * 60 * 1000;
  const today = new Date(); today.setUTCHours(0, 0, 0, 0);

  return {
    taskLists: (s.taskLists ?? []).map((l) => ({ id: l.id, name: l.name })),
    openTasks: (s.tasks ?? []).filter((t) => !t.done).slice(0, 100)
      .map((t) => ({ id: t.id, title: t.title, listId: t.listId ?? "personal", due: t.dueDate ?? null })),
    habits: (s.habits ?? []).filter((h) => !h.isArchived).map((h) => ({ id: h.id, name: h.name })),
    supplements: (s.supplements ?? []).filter((x) => !x.isArchived).map((x) => ({ id: x.id, name: x.name })),
    routines: (s.routines ?? []).map((r) => ({
      id: r.id,
      name: r.name,
      exercises: (r.exercises ?? []).map((e) => exerciseName.get(e.exerciseId) ?? "?"),
    })),
    recentWorkouts: (s.sessions ?? [])
      .filter((w) => w.finishedAt && Date.parse(w.finishedAt) >= twoWeeksAgo)
      .sort((a, b) => Date.parse(b.finishedAt!) - Date.parse(a.finishedAt!))
      .slice(0, 14)
      .map((w) => ({
        name: w.name,
        date: (w.finishedAt ?? "").slice(0, 10),
        exercises: (w.exercises ?? []).map((e) => `${exerciseName.get(e.exerciseId) ?? "?"} (${e.sets?.length ?? 0} sets)`),
      })),
    plannedWorkouts: (s.plannedSessions ?? [])
      .filter((p) => !p.completed && p.date && Date.parse(p.date) >= today.getTime())
      .slice(0, 14)
      .map((p) => ({ date: (p.date ?? "").slice(0, 10), name: p.routineName ?? "" })),
    recentWeights: (s.weightEntries ?? [])
      .slice(-5)
      .map((w) => ({ date: (w.date ?? "").slice(0, 10), kg: w.valueKg })),
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
      const title = text(body.meal, 60);
      if (!title) throw new BadRequest("Say what was eaten.");
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
  const form = (kind: string, title: string, fields: string, button: string) => `
<section class="card" id="${kind}">
  <h3>${title}</h3>
  <form method="post" action="/lifeBot/do?key=${esc(token)}">
    ${k}<input type="hidden" name="kind" value="${kind}">
    ${fields}
    <button type="submit">${button}</button>
  </form>
</section>`;

  const list = (rows: string[]) => rows.length ? `<ul>${rows.join("")}</ul>` : "<p class=muted>None.</p>";
  const libraryByMuscle = new Map<string, Summary["exerciseLibrary"]>();
  for (const e of summary.exerciseLibrary) {
    libraryByMuscle.set(e.muscle, [...(libraryByMuscle.get(e.muscle) ?? []), e]);
  }

  return `<!doctype html>
<html lang="en-GB"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow">
<title>Life for Grok Bot</title>
<style>
:root{color-scheme:light dark;--bg:#f6f7f8;--card:#fff;--text:#16181a;--muted:#5d646b;--line:#dde1e5;--accent:#0f8f83;--ok:#e3f6ee;--bad:#fde8e8}
@media (prefers-color-scheme:dark){:root{--bg:#111315;--card:#1b1e21;--text:#eceef0;--muted:#9aa3ab;--line:#2c3136;--ok:#12332a;--bad:#3a1717}}
body{margin:0;background:var(--bg);color:var(--text);font:16px/1.45 -apple-system,system-ui,sans-serif}
main{max-width:860px;margin:0 auto;padding:16px}
h1{font-size:24px;margin:8px 0}h2{font-size:19px;margin:28px 0 8px}h3{font-size:16px;margin:0 0 10px}
.card{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:14px;margin:10px 0}
label{display:block;margin:8px 0 4px;font-weight:600;font-size:14px}
input,select,textarea{width:100%;box-sizing:border-box;font:inherit;padding:8px;border:1px solid var(--line);border-radius:6px;background:var(--bg);color:var(--text)}
textarea{min-height:150px}
button{margin-top:12px;font:inherit;font-weight:600;padding:9px 16px;border:0;border-radius:6px;background:var(--accent);color:#fff;cursor:pointer}
.muted{color:var(--muted)}.notice{padding:12px;border-radius:8px;margin:12px 0}.ok{background:var(--ok)}.bad{background:var(--bad)}
code{font-size:13px}table{border-collapse:collapse;width:100%;font-size:14px}td,th{border-bottom:1px solid var(--line);padding:5px;text-align:left;vertical-align:top}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(240px,1fr));gap:10px}
</style></head><body><main>
<h1>Life for Grok Bot</h1>
<p class="muted">This private page lets an assistant add things to Will's Life app. Every request goes to the app, which carries it out the next time Life is open on the phone. The status of each request is listed under "Recent requests". Nothing on this page can delete anything.</p>
${notice ? `<div class="notice ${notice.ok ? "ok" : "bad"}" role="status">${esc(notice.text)}</div>` : ""}

<h2>Do something</h2>
${form("createWorkout", "Create a new workout", `
  <label for="w-name">Workout name</label>
  <input id="w-name" name="name" placeholder="e.g. Push day, 3 November" maxlength="60">
  <label for="w-ex">Exercises, one per line: name, sets x reps, rest</label>
  <textarea id="w-ex" name="exercises" placeholder="Bench Press, 4x6-8, 2 min&#10;Incline Dumbbell Press, 3x10, 90s&#10;Cable Fly, 3x12-15, 60s"></textarea>
  <p class="muted">Use exercise names exactly as they appear in the exercise library below. Sets, reps and rest are optional (defaults: 3 x 10, 90s).</p>
  <label for="w-when">Put it in the plan for</label>
  <select id="w-when" name="when"><option value="today">Today</option><option value="tomorrow">Tomorrow</option><option value="none">Don't plan it, just save it</option></select>
  <label for="w-notes">Notes (optional)</label>
  <input id="w-notes" name="notes" maxlength="300">`, "Create workout")}

<div class="grid">
${summary.routines.length ? form("planWorkout", "Plan an existing routine", `
  <label for="p-r">Routine</label><select id="p-r" name="routineId">${options(summary.routines)}</select>
  <label for="p-w">When</label><select id="p-w" name="when"><option value="today">Today</option><option value="tomorrow">Tomorrow</option></select>`, "Plan it") : ""}
${form("addTask", "Add a task", `
  <label for="t-t">Task</label><input id="t-t" name="title" maxlength="120" required>
  <label for="t-l">List</label><select id="t-l" name="listId">${options(summary.taskLists)}</select>
  <label for="t-d">Due</label><select id="t-d" name="due"><option value="today">Today</option><option value="tomorrow">Tomorrow</option><option value="thisWeek">This week</option></select>`, "Add task")}
${summary.openTasks.length ? form("completeTask", "Tick off a task", `
  <label for="c-t">Task</label><select id="c-t" name="taskId">${options(summary.openTasks.map((t) => ({ id: t.id, name: t.title })))}</select>`, "Mark done") : ""}
${summary.habits.length ? form("logHabit", "Log a habit", `
  <label for="h-h">Habit</label><select id="h-h" name="habitId">${options(summary.habits)}</select>
  <label for="h-c">Times</label><input id="h-c" name="count" type="number" min="1" max="20" value="1">`, "Log habit") : ""}
${form("logWater", "Log water", `
  <label for="wa">Glasses</label><input id="wa" name="glasses" type="number" min="1" max="8" value="1">`, "Log water")}
${form("logMeal", "Log a meal", `
  <label for="m">What was eaten</label><input id="m" name="meal" maxlength="60" required>`, "Log meal")}
${form("logWeight", "Log weight", `
  <label for="kg">Kilograms</label><input id="kg" name="kg" type="number" step="0.1" min="25" max="300" required>`, "Log weight")}
${summary.supplements.length ? form("logSupplement", "Log a supplement", `
  <label for="s">Supplement</label><select id="s" name="supplementId">${options(summary.supplements)}</select>`, "Log it") : ""}
</div>

<h2>Recent requests</h2>
<div class="card">${recent.length ? `<table><tr><th>When</th><th>Request</th><th>Status</th></tr>${recent.map((r) =>
  `<tr><td>${esc((r.createdAt ?? "").replace("T", " ").slice(0, 16))}</td><td>${esc(r.what)}${r.result ? `<br><span class="muted">${esc(r.result)}</span>` : ""}</td><td>${esc(r.status === "pending" ? "Waiting for the app" : r.status === "done" ? "Done" : r.status === "claimed" ? "Being applied" : "Couldn't be done")}</td></tr>`).join("")}</table>` : "<p class=muted>Nothing yet.</p>"}</div>

<h2>What's in Life</h2>
<div class="grid">
<section class="card"><h3>Recent workouts (14 days)</h3>${list(summary.recentWorkouts.map((w) => `<li><b>${esc(w.date)}</b> ${esc(w.name)}<br><span class="muted">${esc(w.exercises.join(", "))}</span></li>`))}</section>
<section class="card"><h3>Planned workouts</h3>${list(summary.plannedWorkouts.map((p) => `<li><b>${esc(p.date)}</b> ${esc(p.name)}</li>`))}</section>
<section class="card"><h3>Routines</h3>${list(summary.routines.map((r) => `<li><b>${esc(r.name)}</b><br><span class="muted">${esc(r.exercises.join(", "))}</span></li>`))}</section>
<section class="card"><h3>Open tasks</h3>${list(summary.openTasks.map((t) => `<li>${esc(t.title)} <span class="muted">(${esc(t.listId)}${t.due ? `, ${esc(t.due)}` : ""})</span></li>`))}</section>
<section class="card"><h3>Habits</h3>${list(summary.habits.map((h) => `<li>${esc(h.name)}</li>`))}</section>
<section class="card"><h3>Recent weights</h3>${list(summary.recentWeights.map((w) => `<li>${esc(w.date)}: ${esc(w.kg)} kg</li>`))}</section>
</div>

<h2>Exercise library</h2>
<div class="card">${summary.exerciseLibrary.length ? [...libraryByMuscle.entries()].map(([muscle, items]) =>
  `<p><b>${esc(muscle || "Other")}</b>: ${items.map((e) => `${esc(e.name)} <span class="muted">(${esc(e.equipment)})</span>`).join(", ")}</p>`).join("") : "<p class=muted>The app hasn't synced its library yet.</p>"}</div>

<p class="muted">For agents that prefer JSON: GET <code>lifeBot/api/state?key=…</code> returns all of the above, and POST <code>lifeBot/api/do?key=…</code> with a JSON body such as <code>{"kind":"createWorkout","name":"Legs","exercises":"Squat, 5x5, 3 min\\nLeg Press, 3x10","when":"today"}</code> does the same as the forms.</p>
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
