# Echo — Database Schema

Echo uses **DynamoDB** (a NoSQL key-value store). Locally it runs as **dynalite**
on `http://localhost:8000`; in production it's AWS DynamoDB. Same tables either way.

## How to SEE the database (your "pgAdmin")
1. Make sure the local DB is running — double-click **`start-local-services.bat`**.
2. Open **http://localhost:8001** in a browser (the `dynamodb-admin` GUI).
3. Click any table to view/edit its rows.

Command-line check (counts):
```
venv\Scripts\python -c "import boto3; d=boto3.resource('dynamodb',region_name='us-east-1',endpoint_url='http://localhost:8000',aws_access_key_id='local',aws_secret_access_key='local'); [print(t,':',len(d.Table(t).scan()['Items'])) for t in ['whisperflow-users','whisperflow-history','whisperflow-feedback','whisperflow-events']]"
```

## Tables

DynamoDB has no fixed columns (only the key fields are defined); other attributes
are per-item. Below is what Echo actually writes.

### 1. `whisperflow-users`  *(local test login only; in production this is AWS Cognito)*
| Field | Type | Key | Notes |
|---|---|---|---|
| `email` | String | **Partition key** | the account email |
| `password_hash` | String | | pbkdf2 hash (never plain text) |
| `created` | String | | timestamp `YYYYMMDD_HHMMSS` |

> In production, accounts live in **Cognito**, not here. This table is only the
> stand-in so login can be tested without AWS.

### 2. `whisperflow-history`  — saved transcriptions
| Field | Type | Key | Notes |
|---|---|---|---|
| `userId` | String | **Partition key** | the user's id/email |
| `timestamp` | String | **Sort key** | `YYYYMMDD_HHMMSS` |
| `text` | String | | the transcribed (grammar-corrected) text |
| `model` | String | | e.g. `whisper-large-v3` |

### 3. `whisperflow-feedback`  — in-app feedback
| Field | Type | Key | Notes |
|---|---|---|---|
| `userId` | String | **Partition key** | |
| `timestamp` | String | **Sort key** | |
| `rating` | Number | | 1–5 stars |
| `comment` | String | | free text |
| `transcription_id` | String | | optional link to a transcript |

### 4. `whisperflow-events`  — usage / analytics tracking
| Field | Type | Key | Notes |
|---|---|---|---|
| `userId` | String | **Partition key** | |
| `timestamp` | String | **Sort key** | microsecond precision |
| `event` | String | | `app_open`, `login`, `register`, `transcribe`, `retry`, `feedback` |
| `meta` | Map | | extra info, e.g. `{words: 6}` |

## Going to AWS later (no code change)
- Drop `dynamodb_endpoint_url` from `config.json`, add real AWS keys → the same
  `history`/`feedback`/`events` tables get created in AWS DynamoDB.
- `whisperflow-users` is replaced by **Cognito** (set the `cognito_*` keys).

## Note on table names
Tables are still prefixed `whisperflow-` (legacy name) — internal only, not shown
to users. Can be renamed to `echo-*` when provisioning real AWS if desired.
