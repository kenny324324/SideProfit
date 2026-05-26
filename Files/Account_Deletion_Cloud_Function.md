# Account-deletion Cloud Function — deploy notes

**Status:** source committed (`Functions/index.js`), **not deployed**.

App Store guideline 5.1.1(v) requires server-side data deletion when a user deletes their account. The client (`AuthService.deleteAccount`) writes a `users/{uid}/deletionRequests/{requestId}` doc while still authenticated; this Cloud Function fires off that write and cascade-deletes every Firestore doc the user owns. See [Functions/index.js](../Functions/index.js) for the implementation + design notes.

## Before deploy

1. Install the Firebase CLI if it's not on this machine:
   ```bash
   npm install -g firebase-tools
   firebase login
   ```
2. Confirm you're pointed at `sideprofit-dev` (or whichever project you're deploying to):
   ```bash
   firebase use sideprofit-dev
   ```
   First-time setup may need `firebase use --add` to register the alias.
3. From the repo root, install the function deps:
   ```bash
   cd Functions && npm install && cd -
   ```

## Deploy steps

From the repo root:

```bash
# Security rules first (no-op safe to re-run)
firebase deploy --only firestore:rules

# Cloud Function — region is asia-east1, matches Firestore
firebase deploy --only functions

# Or both at once
firebase deploy --only firestore:rules,functions
```

The first function deploy enables the Cloud Functions API on the project and provisions the `cascadeDeleteUser` trigger. Subsequent deploys just push code updates.

## Verify after deploy

1. In the iOS app: sign in → create one project → settings → 「刪除帳號」 → confirm.
2. Open the Firebase Console:
   - **Authentication → Users** — the deleted account is gone.
   - **Firestore → projects collection** — the project doc you created is gone.
   - **Firestore → users/{uid}** — node is gone.
3. **Functions → Logs** should show `Cascade delete complete for uid=…`.

## Cost expectation

Free tier (Spark plan) gives 125k invocations / 40k GB-seconds compute per month. Account deletion is a low-frequency event — even a few hundred deletes a month sits comfortably under the free tier. Once the app is on the Blaze plan for production scale, each cascade run is fractions of a cent (the limiting factor is `ENTITY_COLLECTIONS.length × 1 read query + N delete writes`).

## Known limitations

- **No retries on partial failure.** If the function throws mid-cascade (e.g., Firestore quota exhaustion), only the entities deleted before the throw are removed. The deletionRequest doc stays so the user can re-trigger via support contact. Add a Pub/Sub retry policy post-launch if this ever bites.
- **Storage objects aren't covered.** DevCal doesn't store any user-uploaded files yet; if `iconImageData` ever migrates from inline `Data` to a Cloud Storage URL, extend `cascadeDeleteUser` to also clear `gs://sideprofit-*/users/{uid}/`.
- **Cloud Function runs asynchronously.** The user sees the local data wiped + Firebase Auth user gone immediately (client-side), but the server cascade can take a few seconds depending on doc volume. For MVP this is invisible to the user.
