# Firestore Rules Tests

Regression suite for `../firestore.rules`. 40 assertions covering every
collection, every query shape the Android client issues, and the corresponding
denial cases (cross-tenant access, ownerUid hijacking, unfiltered list queries,
hard deletes, type violations, missing fields, collection enumeration).

## Run

Requires Node.js and a JDK (the Firestore emulator is a Java process).

```bash
cd firestore-tests
npm init -y
npm install firebase-tools @firebase/rules-unit-testing firebase
cp ../firebase.json ../firestore.indexes.json .

# JDK must be on PATH — Android Studio's bundled JBR works:
export JAVA_HOME="/c/Program Files/Android/Android Studio/jbr"   # Windows: $env:JAVA_HOME=...
export PATH="$JAVA_HOME/bin:$PATH"

npx firebase emulators:exec --only firestore --project demo-echo "node rules.test.js"
```

Expected output ends with:

```
════ 40 passed, 0 failed ════
```

Nothing touches the live `echo-mirai` project — the emulator runs locally
against the `demo-echo` project ID, which Firebase reserves for offline use.

## What the suite locks in

- `transcripts` / `transcriptVersions` list queries succeed **only** when they
  carry `whereEqualTo("ownerUid", <caller uid>)`. This is the exact shape
  `restoreRecentHistory()` and `downloadRemoteUpdates()` use.
- The previously broken `whereIn("transcriptId", …)` version query is asserted
  to be **denied**, so it cannot be reintroduced without the test failing.
- `aiJobs` and `userPreferences` and `users` cannot be enumerated.
- Nullable Kotlin fields (`audioPath`, `promptTemplateId`, `startedAt`,
  `completedAt`, `processingTimeMs`, `errorMessage`) are accepted as `null`
  and as their populated type.
- Hard deletes are denied everywhere; deletion is soft (`deleted = true`).
