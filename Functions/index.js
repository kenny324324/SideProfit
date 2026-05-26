// Cloud Function: account-deletion cascade.
//
// App Store guideline 5.1.1(v) requires that when a user deletes their
// account, all of their server-stored data goes away too. The client
// (AuthService.deleteAccount) writes a `users/{uid}/deletionRequests/{requestId}`
// doc while still authenticated; this function fires off that write and
// removes every doc the user owns (matched by `ownerUid == uid`) plus the
// per-user singleton at `subscriptionStatus/{uid}`.
//
// Why this lives server-side instead of doing it from the iOS client:
//   - The client may have unsynced operations queued locally; tombstoning
//     them through the repository layer only works if the device finishes
//     a sync pass before delete. A server-side cascade is the only way to
//     guarantee cleanup if the user uninstalls mid-flow.
//   - Once the Firebase Auth user is deleted, the client can no longer
//     write to Firestore — so the cascade has to run with admin creds.
//
// Deploy with `firebase deploy --only functions` from the repo root.
// Region matches Firestore: asia-east1.

const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");
const logger = require("firebase-functions/logger");

initializeApp();
const db = getFirestore();

// Every root-level collection a user owns. Keep in sync with the
// SyncEntityKind enum in DevCal (Core/Data/Sync/PendingSyncOperation.swift).
const ENTITY_COLLECTIONS = [
  "projects",
  "transactions",
  "timeLogs",
  "categoryItems",
  "milestones",
];

const BATCH_SIZE = 400;

exports.cascadeDeleteUser = onDocumentCreated(
  {
    document: "users/{uid}/deletionRequests/{requestId}",
    region: "asia-east1",
  },
  async (event) => {
    const uid = event.params.uid;
    const requestId = event.params.requestId;
    logger.info(`Cascade delete starting for uid=${uid}, requestId=${requestId}`);

    try {
      for (const collection of ENTITY_COLLECTIONS) {
        const deleted = await deleteCollectionForOwner(collection, uid);
        logger.info(`Deleted ${deleted} doc(s) from ${collection} for uid=${uid}`);
      }

      // Per-user singleton — doc id IS the uid, no `ownerUid` filter needed.
      await db
        .collection("subscriptionStatus")
        .doc(uid)
        .delete()
        .catch((err) => logger.warn("subscriptionStatus delete failed", err));

      // Remove the deletion-request doc itself so the user node disappears.
      await db
        .collection("users")
        .doc(uid)
        .collection("deletionRequests")
        .doc(requestId)
        .delete()
        .catch((err) => logger.warn("deletionRequest cleanup failed", err));

      logger.info(`Cascade delete complete for uid=${uid}`);
    } catch (err) {
      logger.error(`Cascade delete failed for uid=${uid}`, err);
      throw err;
    }
  }
);

/**
 * Delete every document in `collection` where `ownerUid == uid`. Batches
 * 400 deletes at a time (Firestore caps each WriteBatch at 500 ops).
 * @returns the number of documents deleted.
 */
async function deleteCollectionForOwner(collection, uid) {
  let totalDeleted = 0;
  // eslint-disable-next-line no-constant-condition
  while (true) {
    const snapshot = await db
      .collection(collection)
      .where("ownerUid", "==", uid)
      .limit(BATCH_SIZE)
      .get();

    if (snapshot.empty) return totalDeleted;

    const batch = db.batch();
    snapshot.docs.forEach((doc) => batch.delete(doc.ref));
    await batch.commit();
    totalDeleted += snapshot.size;

    if (snapshot.size < BATCH_SIZE) return totalDeleted;
  }
}
