import { getFirestore, FieldValue } from "firebase-admin/firestore";

/**
 * Rate and spend limits, enforced server-side.
 *
 * On the server because a limit the client enforces is not a limit: a bug, a
 * retry loop or a reinstalled app with cleared state would sail past it, and
 * the bill arrives regardless. The counters live in Firestore under the user's
 * own document so they survive reinstalls and are shared across devices.
 */

/** Rough per-million-token prices, used only for the ceiling. */
export interface Pricing {
  inputPerMillion: number;
  outputPerMillion: number;
}

export interface Limits {
  /** Calls allowed in a rolling hour. */
  hourlyCalls: number;
  /** Hard stop for the calendar month, in the currency of `pricing`. */
  monthlyCostCeiling: number;
  pricing: Pricing;
}

export interface UsageSnapshot {
  callsThisHour: number;
  callsThisMonth: number;
  costThisMonth: number;
}

export class LimitExceeded extends Error {
  constructor(public readonly kind: "rate" | "cost", message: string) {
    super(message);
    this.name = "LimitExceeded";
  }
}

function monthKey(now: Date): string {
  return `${now.getUTCFullYear()}-${String(now.getUTCMonth() + 1).padStart(2, "0")}`;
}

/**
 * Reserves a call slot, or throws.
 *
 * Runs in a transaction and increments *before* the model is called, not
 * after. Counting on the way back would let a burst of concurrent requests all
 * read the same count, all decide they were under the limit, and all proceed —
 * which is precisely the situation a spend ceiling exists to prevent. An
 * abandoned reservation costs one phantom call; the alternative costs money.
 */
export async function reserveCall(
  uid: string,
  limits: Limits,
  now: Date = new Date()
): Promise<UsageSnapshot> {
  const db = getFirestore();
  const ref = db
    .collection("users")
    .doc(uid)
    .collection("coachUsage")
    .doc(monthKey(now));

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const data = snap.exists ? snap.data() ?? {} : {};

    const costThisMonth = Number(data.costThisMonth ?? 0);
    if (costThisMonth >= limits.monthlyCostCeiling) {
      throw new LimitExceeded(
        "cost",
        "The monthly limit for AI coaching has been reached."
      );
    }

    // A rolling hour held as a list of timestamps rather than a counter with a
    // reset, so the limit can't be dodged by calling either side of a boundary.
    const recent: number[] = Array.isArray(data.recentCallTimes)
      ? (data.recentCallTimes as number[])
      : [];
    const cutoff = now.getTime() - 60 * 60 * 1000;
    const withinHour = recent.filter((t) => t > cutoff);

    if (withinHour.length >= limits.hourlyCalls) {
      throw new LimitExceeded(
        "rate",
        "Too many coach requests in the last hour. Try again shortly."
      );
    }

    withinHour.push(now.getTime());

    tx.set(
      ref,
      {
        recentCallTimes: withinHour,
        callsThisMonth: FieldValue.increment(1),
        costThisMonth,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    return {
      callsThisHour: withinHour.length,
      callsThisMonth: Number(data.callsThisMonth ?? 0) + 1,
      costThisMonth,
    };
  });
}

/**
 * Records what a completed call actually cost.
 *
 * Separate from the reservation because token counts are only known afterwards.
 * A failed call leaves its reservation in place and adds no cost — the right
 * way round, since a failure that reset the counter would let a persistent
 * error be retried without limit.
 */
export async function recordUsage(
  uid: string,
  tokens: { promptTokens: number; outputTokens: number },
  pricing: Pricing,
  now: Date = new Date()
): Promise<number> {
  const cost =
    (tokens.promptTokens / 1_000_000) * pricing.inputPerMillion +
    (tokens.outputTokens / 1_000_000) * pricing.outputPerMillion;

  const db = getFirestore();
  const ref = db
    .collection("users")
    .doc(uid)
    .collection("coachUsage")
    .doc(monthKey(now));

  await ref.set(
    {
      costThisMonth: FieldValue.increment(cost),
      promptTokensThisMonth: FieldValue.increment(tokens.promptTokens),
      outputTokensThisMonth: FieldValue.increment(tokens.outputTokens),
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true }
  );

  return cost;
}

/** Current usage, for the settings screen. Never throws. */
export async function readUsage(
  uid: string,
  now: Date = new Date()
): Promise<UsageSnapshot> {
  const db = getFirestore();
  const snap = await db
    .collection("users")
    .doc(uid)
    .collection("coachUsage")
    .doc(monthKey(now))
    .get();

  const data = snap.exists ? snap.data() ?? {} : {};
  const cutoff = now.getTime() - 60 * 60 * 1000;
  const recent: number[] = Array.isArray(data.recentCallTimes)
    ? (data.recentCallTimes as number[])
    : [];

  return {
    callsThisHour: recent.filter((t) => t > cutoff).length,
    callsThisMonth: Number(data.callsThisMonth ?? 0),
    costThisMonth: Number(data.costThisMonth ?? 0),
  };
}
