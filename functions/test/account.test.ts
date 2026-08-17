/**
 * Tests for the account-deletion purge, against the Firestore emulator.
 *
 * The thing being verified is that deletion is *complete*. A purge that leaves
 * the spend counters behind, or that removes the snapshot but not the
 * subcollection it lives in, would still report success — and the user would
 * have been told their health data was gone when it wasn't. Under UK GDPR that
 * is a false statement about erasure, not a loose end.
 *
 * `recursiveDelete` is the piece doing the work, and it is exactly the kind of
 * call that looks obviously correct and quietly isn't if the reference is a
 * document rather than a collection, or vice versa. Hence real writes, a real
 * delete, and a real read-back.
 */
import { initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import { purgeUserData } from "../src/account";

const ALICE = "alice-uid";
const BOB = "bob-uid";

beforeAll(() => {
  // emulators:exec sets this. Without it these tests would silently talk to a
  // real project, which for a suite whose entire job is deleting things is a
  // failure mode worth refusing outright rather than detecting later.
  if (!process.env.FIRESTORE_EMULATOR_HOST) {
    throw new Error(
      "FIRESTORE_EMULATOR_HOST is not set — run these through `npm test`, " +
        "which starts the emulator. Refusing to run against a real project."
    );
  }
  initializeApp({ projectId: "life-rules-test" });
});

/** Writes a realistic account: a state snapshot and two months of usage. */
async function seedAccount(uid: string) {
  const db = getFirestore();
  await db.doc(`users/${uid}/state/snapshot`).set({
    json: '{"tasks":[],"healthDays":{}}',
    schemaVersion: 1,
  });
  await db.doc(`users/${uid}/coachUsage/2026-07`).set({ calls: 12, costUsd: 0.03 });
  await db.doc(`users/${uid}/coachUsage/2026-08`).set({ calls: 4, costUsd: 0.01 });
}

async function countDocs(uid: string): Promise<number> {
  const db = getFirestore();
  const [state, usage] = await Promise.all([
    db.collection(`users/${uid}/state`).get(),
    db.collection(`users/${uid}/coachUsage`).get(),
  ]);
  return state.size + usage.size;
}

beforeEach(async () => {
  const db = getFirestore();
  await db.recursiveDelete(db.collection("users"));
});

describe("purgeUserData", () => {
  it("removes the state snapshot", async () => {
    await seedAccount(ALICE);
    await purgeUserData(ALICE);

    const doc = await getFirestore().doc(`users/${ALICE}/state/snapshot`).get();
    expect(doc.exists).toBe(false);
  });

  it("removes every month of usage, not just the current one", async () => {
    await seedAccount(ALICE);
    await purgeUserData(ALICE);

    const usage = await getFirestore().collection(`users/${ALICE}/coachUsage`).get();
    expect(usage.size).toBe(0);
  });

  it("leaves nothing at all behind under the user", async () => {
    await seedAccount(ALICE);
    expect(await countDocs(ALICE)).toBe(3);

    await purgeUserData(ALICE);
    expect(await countDocs(ALICE)).toBe(0);
  });

  it("takes subcollections nobody thought to enumerate", async () => {
    // A future feature adding users/{uid}/somethingNew must not survive a
    // deletion written before it existed. recursiveDelete is chosen over
    // deleting known paths for exactly this reason, so it is worth asserting.
    await seedAccount(ALICE);
    await getFirestore().doc(`users/${ALICE}/somethingNew/doc`).set({ a: 1 });

    await purgeUserData(ALICE);

    const leftover = await getFirestore()
      .collection(`users/${ALICE}/somethingNew`)
      .get();
    expect(leftover.size).toBe(0);
  });

  it("does not touch anybody else's account", async () => {
    await seedAccount(ALICE);
    await seedAccount(BOB);

    await purgeUserData(ALICE);

    expect(await countDocs(ALICE)).toBe(0);
    expect(await countDocs(BOB)).toBe(3);
  });

  it("is safe to run twice — a retry must not fail", async () => {
    await seedAccount(ALICE);
    await purgeUserData(ALICE);
    await expect(purgeUserData(ALICE)).resolves.toBeUndefined();
  });

  it("succeeds on an account that never stored anything", async () => {
    await expect(purgeUserData("never-used-uid")).resolves.toBeUndefined();
  });

  it("refuses an empty uid rather than deleting the collection root", async () => {
    // `users/` + "" would be a malformed path at best and a whole-collection
    // delete at worst. Guarded explicitly.
    await seedAccount(ALICE);
    await expect(purgeUserData("")).rejects.toThrow();
    expect(await countDocs(ALICE)).toBe(3);
  });
});
