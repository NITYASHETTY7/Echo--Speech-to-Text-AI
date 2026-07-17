# Local Testing — run the v1.1 cloud features with NO AWS

This runs everything on your machine (your Postgres+pgAdmin analogy):

| Cloud piece | Local stand-in | pgAdmin analogy |
|---|---|---|
| DynamoDB (history / feedback / events / users) | **dynalite** (pure Node, no Java/Docker) | the database engine |
| Browse the tables | **dynamodb-admin** (web GUI at :8001) | pgAdmin4 |
| Grammar + bullet structuring | **Groq** (your existing key) | — |
| Login (Gmail + email) | **local email/password** (throwaway, in dynalite) | — |

> Real **"Sign in with Google"** still needs real AWS Cognito + Google — it's an
> external OAuth flow that cannot run locally. The local login is email/password only.

Already installed in this project: `dynalite`, `dynamodb-admin` (global npm).

---

## One-time
Tables are already created. To recreate them later:
```
python setup_local_db.py
```

## Each time you want to test (3 terminals)

**Terminal 1 — database engine:**
```
dynalite --port 8000 --path ./dynalite-data
```

**Terminal 2 — GUI (pgAdmin equivalent), optional:**
```
set DYNAMO_ENDPOINT=http://localhost:8000
dynamodb-admin
```
→ open http://localhost:8001 to browse rows.

**Terminal 3 — the app:**
```
npm start
```

## config.json (already set for you)
These keys put the app in local mode (your real `api_key` is untouched; a
backup was saved to `config.backup.json`):
```json
"auth_mode": "local",
"dynamodb_endpoint_url": "http://localhost:8000"
```

Grammar correction runs **only** on AWS Bedrock (`grammar_correction_enabled`,
default `true`). It needs a `bedrock_api_key`; without one, transcripts are left
uncorrected. Groq is the speech-to-text engine and never does grammar correction.

## What to verify
1. **Login** — on launch a login screen appears (amber "Local test mode" badge).
   "No account? Create one" → register → app opens. Re-launch → sign in.
2. **Grammar + structuring** — needs a `bedrock_api_key`. Dictate
   `"buy milk eggs and bread also call mom"` → becomes bullet points; a single
   sentence stays prose. Without a Bedrock key the transcript passes through
   verbatim and the log shows `[bedrock] grammar correction skipped`.
3. **Cloud DB write** — after a transcription, open dynamodb-admin (:8001) →
   `whisperflow-history` has a row under your email.
4. **Feedback** — 💬 Feedback → row in `whisperflow-feedback`.
5. **Analytics** — `whisperflow-events` gets `app_open`, `login`, `transcribe`, etc.
6. **Retry** — 🔄 Retry re-transcribes the last clip (writes a `retry` event).

---

## Revert to plain local (no login) or go to AWS

**Turn the local login off** — remove `"auth_mode": "local"` (or restore
`config.backup.json`). The app then runs with no login (dev mode).

**Go to real AWS later (no code change)** — in `config.json`:
1. Remove `dynamodb_endpoint_url`; add real `dynamodb_access_key_id` / `dynamodb_secret_access_key`.
2. Add a real `bedrock_api_key` (and enable Bedrock model access) to turn on grammar correction.
3. Add the `cognito_*` keys to switch on real Cognito + Google login.

The history/feedback/events tables you made locally are exactly what you create in AWS.
```
