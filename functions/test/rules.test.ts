/**
 * Security rules tests for firestore.rules.
 *
 * These run against the Firestore emulator, so they exercise the real rules
 * engine rather than an approximation of it:
 *
 *   npm test          (starts the emulator via firebase emulators:exec)
 *
 * Most of what follows asserts that something is DENIED. That is deliberate.
 * Firestore rules are additive and default-deny, so the security properties of
 * `firestore.rules` are carried by the grants it does not contain — and an
 * omission is exactly the kind of thing a later edit reintroduces by accident
 * while "tidying up". A test that fails loudly when someone adds a
 * `match /coachUsage/{month}` block is the only durable way to protect it.
 */
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  type RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { afterAll, beforeAll, beforeEach, describe, it } from "vitest";

const ALICE = "alice-uid";
const BOB = "bob-uid";

let env: RulesTestEnvironment;

/** A valid snapshot payload, matching what FirestoreSync.swift actually sends. */
function snapshotPayload(json = '{"tasks":[]}') {
  return {
    json,
    updatedAt: new Date(),
    clientUpdatedAt: new Date(),
    schemaVersion: 1,
  };
}

beforeAll(async () => {
  env = await initializeTestEnvironment({
    projectId: "life-rules-test",
    firestore: {
      rules: readFileSync(resolve(__dirname, "../../firestore.rules"), "utf8"),
      host: "127.0.0.1",
      port: 8080,
    },
  });
});

afterAll(async () => {
  await env?.cleanup();
});

beforeEach(async () => {
  await env.clearFirestore();
});

describe("/users/{uid}/state/snapshot — the app state", () => {
  it("lets the owner write their own snapshot", async () => {
    const db = env.authenticatedContext(ALICE).firestore();
    await assertSucceeds(
      db.doc(`users/${ALICE}/state/snapshot`).set(snapshotPayload())
    );
  });

  it("lets the owner read their own snapshot back", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await ctx
        .firestore()
        .doc(`users/${ALICE}/state/snapshot`)
        .set(snapshotPayload());
    });

    const db = env.authenticatedContext(ALICE).firestore();
    await assertSucceeds(db.doc(`users/${ALICE}/state/snapshot`).get());
  });

  it("does not let another signed-in user read it", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await ctx
        .firestore()
        .doc(`users/${ALICE}/state/snapshot`)
        .set(snapshotPayload('{"secret":"alice health data"}'));
    });

    const db = env.authenticatedContext(BOB).firestore();
    await assertFails(db.doc(`users/${ALICE}/state/snapshot`).get());
  });

  it("does not let another signed-in user overwrite it", async () => {
    const db = env.authenticatedContext(BOB).firestore();
    await assertFails(
      db.doc(`users/${ALICE}/state/snapshot`).set(snapshotPayload())
    );
  });

  it("does not let an unauthenticated client read or write", async () => {
    const db = env.unauthenticatedContext().firestore();
    await assertFails(db.doc(`users/${ALICE}/state/snapshot`).get());
    await assertFails(
      db.doc(`users/${ALICE}/state/snapshot`).set(snapshotPayload())
    );
  });

  it("rejects a document id other than 'snapshot'", async () => {
    const db = env.authenticatedContext(ALICE).firestore();
    await assertFails(
      db.doc(`users/${ALICE}/state/somethingelse`).set(snapshotPayload())
    );
  });

  it("rejects a payload whose json is not a string", async () => {
    const db = env.authenticatedContext(ALICE).firestore();
    await assertFails(
      db.doc(`users/${ALICE}/state/snapshot`).set({
        ...snapshotPayload(),
        json: { tasks: [] },
      })
    );
  });

  it("rejects a json payload over the 1 MiB document ceiling", async () => {
    const db = env.authenticatedContext(ALICE).firestore();
    await assertFails(
      db
        .doc(`users/${ALICE}/state/snapshot`)
        .set(snapshotPayload("x".repeat(1_000_001)))
    );
  });

  it("accepts a large but legal payload", async () => {
    const db = env.authenticatedContext(ALICE).firestore();
    await assertSucceeds(
      db
        .doc(`users/${ALICE}/state/snapshot`)
        .set(snapshotPayload("x".repeat(500_000)))
    );
  });
});

describe("/users/{uid}/coachUsage/{month} — the spend ceiling", () => {
  /**
   * The whole point. `reserveCall` in functions/src/limits.ts enforces the
   * hourly request limit and the monthly cost ceiling by reading and writing
   * this document through the Admin SDK, which bypasses rules. That ceiling is
   * the only thing between a compromised account and an unbounded Gemini bill,
   * so a client write grant here — even one correctly scoped to the owner —
   * would let any user zero their own counter and spend without limit.
   *
   * If one of these starts failing, someone has added a match block for
   * coachUsage. Do not "fix" the test.
   */
  it("does not let the owner write their own usage counter", async () => {
    const db = env.authenticatedContext(ALICE).firestore();
    await assertFails(
      db.doc(`users/${ALICE}/coachUsage/2026-08`).set({ calls: 0, costUsd: 0 })
    );
  });

  it("does not let the owner zero an existing counter", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await ctx
        .firestore()
        .doc(`users/${ALICE}/coachUsage/2026-08`)
        .set({ calls: 99, costUsd: 4.2 });
    });

    const db = env.authenticatedContext(ALICE).firestore();
    await assertFails(
      db.doc(`users/${ALICE}/coachUsage/2026-08`).update({ calls: 0, costUsd: 0 })
    );
  });

  it("does not let the owner read it either — usage comes from the callable", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await ctx
        .firestore()
        .doc(`users/${ALICE}/coachUsage/2026-08`)
        .set({ calls: 5, costUsd: 0.01 });
    });

    const db = env.authenticatedContext(ALICE).firestore();
    await assertFails(db.doc(`users/${ALICE}/coachUsage/2026-08`).get());
  });

  it("does not let another user touch it", async () => {
    const db = env.authenticatedContext(BOB).firestore();
    await assertFails(db.doc(`users/${ALICE}/coachUsage/2026-08`).get());
    await assertFails(
      db.doc(`users/${ALICE}/coachUsage/2026-08`).set({ calls: 0 })
    );
  });
});

describe("everything else", () => {
  it("denies the user document itself", async () => {
    const db = env.authenticatedContext(ALICE).firestore();
    await assertFails(db.doc(`users/${ALICE}`).set({ name: "Alice" }));
    await assertFails(db.doc(`users/${ALICE}`).get());
  });

  it("denies collections the app does not use", async () => {
    const db = env.authenticatedContext(ALICE).firestore();
    await assertFails(db.doc("anything/else").set({ a: 1 }));
    await assertFails(db.doc(`users/${ALICE}/somethingNew/doc`).set({ a: 1 }));
  });
});
