/**
 * Account deletion.
 *
 * App Review guideline 5.1.1(v): an app that lets you create an account must
 * let you delete it from inside the app. Life signs in with Apple, and Settings
 * previously offered only "Reset All Data" (which clears the device) and "Sign
 * Out" (which clears nothing) — neither of which is deletion.
 *
 * This is the server half. It runs with the Admin SDK for two reasons that both
 * matter:
 *
 *   - The client cannot delete its own Firestore data. Security rules grant no
 *     write access to `coachUsage` at all (see firestore.rules), deliberately,
 *     so the spend ceiling cannot be zeroed by the account it limits. A purge
 *     therefore has to come from a caller that bypasses rules.
 *   - `getAuth().deleteUser` has no recent-sign-in requirement, unlike the
 *     client SDK's `delete()`, which fails with `requires-recent-login` on any
 *     session more than a few minutes old. Doing it here means the user is not
 *     asked to sign in again in order to leave.
 *
 * Revoking the Sign in with Apple token is the *client's* job and happens
 * before this is called — it needs an authorization code that only a fresh
 * Apple sign-in produces, which the server never sees.
 */
import { getAuth } from "firebase-admin/auth";
import { getFirestore } from "firebase-admin/firestore";
import { onCall, HttpsError, CallableRequest } from "firebase-functions/v2/https";

/**
 * Removes everything stored under `/users/{uid}`.
 *
 * `recursiveDelete` takes the subcollections with it — `state/snapshot` holds
 * the entire app state including all health data, and `coachUsage/{month}`
 * holds the spend counters. Both go.
 *
 * Separated from the callable so it can be tested against the emulator without
 * standing up auth. Returns nothing on success and throws on failure: a purge
 * that partly worked must not be reported as done.
 */
export async function purgeUserData(uid: string): Promise<void> {
  if (!uid) {
    throw new Error("purgeUserData called without a uid");
  }
  const db = getFirestore();
  await db.recursiveDelete(db.collection("users").doc(uid));
}

/**
 * Deletes the caller's account and everything stored against it.
 *
 * Data first, then the account. If the second step fails the user is left able
 * to sign in to an empty account, which is recoverable and honest; the reverse
 * order would leave orphaned health data behind with no signed-in user who
 * could ever ask for it again, which is neither.
 */
export const deleteAccount = onCall(
  { region: "europe-west2", memory: "256MiB", maxInstances: 3 },
  async (request: CallableRequest<unknown>) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "Sign in to delete your account.");
    }

    try {
      await purgeUserData(uid);
    } catch (error) {
      // Names and statuses only. The thing being deleted is a year of someone's
      // health data and the log is the one place it must not reappear.
      console.error("deleteAccount: purge failed", {
        step: "firestore",
        error: error instanceof Error ? error.name : typeof error,
      });
      throw new HttpsError(
        "internal",
        "Your data could not be deleted. Nothing has been removed — please try again."
      );
    }

    try {
      await getAuth().deleteUser(uid);
    } catch (error) {
      // `user-not-found` means a previous attempt got this far and the retry has
      // nothing left to do. That is success, not failure — reporting an error
      // would trap the user in a loop they cannot complete.
      const code = (error as { code?: string })?.code;
      if (code !== "auth/user-not-found") {
        console.error("deleteAccount: auth deletion failed", {
          step: "auth",
          code: code ?? "unknown",
        });
        throw new HttpsError(
          "internal",
          "Your data was deleted, but the account itself could not be removed. Please try again."
        );
      }
    }

    return { deleted: true };
  }
);
