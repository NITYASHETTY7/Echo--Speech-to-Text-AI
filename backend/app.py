from flask import Flask, render_template, request, jsonify, g
import os
import sys
import socket
import re
from datetime import datetime, timedelta
import json
import time
import threading
from functools import wraps
from groq import Groq, AuthenticationError, APIConnectionError

# Force UTF-8 stdout/stderr so the emoji log lines don't crash on a Windows
# cp1252 console (notably inside the frozen .exe, where PYTHONUTF8 may be unset).
try:
    sys.stdout.reconfigure(encoding='utf-8')
    sys.stderr.reconfigure(encoding='utf-8')
except Exception:
    pass

# When frozen by PyInstaller, bundled data (templates/) is extracted to _MEIPASS,
# so point Flask's template folder there. In dev, default resolution is used.
if getattr(sys, 'frozen', False):
    _bundle_dir = getattr(sys, '_MEIPASS', os.path.dirname(os.path.abspath(__file__)))
    # Both templates/ and static/ are bundled into _MEIPASS by PyInstaller, so point
    # Flask at them explicitly. static_folder must be set too (it does NOT default to
    # _MEIPASS) or /static/vendor/* — the locally-bundled React/Babel/Tailwind that
    # replaced the CDN — would 404 and the UI would render as a blank window.
    app = Flask(__name__,
                template_folder=os.path.join(_bundle_dir, 'templates'),
                static_folder=os.path.join(_bundle_dir, 'static'))
else:
    app = Flask(__name__)

# ── Writable data directory ──────────────────────────────────────────────────
# In a packaged build the app lives in a read-only location (e.g. Program Files),
# so every file the backend writes must live in a per-user writable folder.
# Electron passes that folder via ECHO_DATA_DIR; in dev we fall back to the
# project directory so local behaviour is unchanged.
def _resolve_data_dir():
    d = os.environ.get('ECHO_DATA_DIR')          # packaged: Electron's userData
    if d:
        os.makedirs(d, exist_ok=True)
        return d
    if getattr(sys, 'frozen', False):            # frozen exe, no env → home folder
        d = os.path.join(os.path.expanduser('~'), '.echo')
        os.makedirs(d, exist_ok=True)
        return d
    return os.path.dirname(os.path.abspath(__file__))  # dev → project dir (as before)

DATA_DIR = _resolve_data_dir()

# Directory setup (all paths are absolute, under DATA_DIR)
RECORDINGS_DIR = os.path.join(DATA_DIR, "recordings")
HISTORY_FILE   = os.path.join(DATA_DIR, "transcription_history.json")
CONFIG_FILE    = os.path.join(DATA_DIR, "config.json")
PORT_FILE      = os.path.join(DATA_DIR, "server_port.txt")  # communicate port to Electron

# Defaults for config-driven settings (Phase 3)
DEFAULT_HISTORY_RETENTION_DAYS = 30  # D5 / BUG-16 — 0 means keep forever
DEFAULT_LANGUAGE = "en"              # BUG-20 — ISO-639-1 code, or "auto"

# AWS Partner Revenue Measurement — attributes Bedrock usage to the Echo partner account
AWS_PRM_USER_AGENT = "APN_1.1/pc_3qhcztbtv5n3274pdesyn4o09$"

os.makedirs(RECORDINGS_DIR, exist_ok=True)

def _user_recordings_dir(user_id):
    """Per-user recordings subdir (filesystem-safe), created on demand. Keeps one
    user's audio isolated from another's so multi-user hosting can't cross-wipe."""
    safe = ''.join(c if (c.isalnum() or c in '._-@') else '_'
                   for c in str(user_id or 'dev-user'))[:64] or 'dev-user'
    d = os.path.join(RECORDINGS_DIR, safe)
    os.makedirs(d, exist_ok=True)
    return d

def _prune_user_recordings(user_dir, keep_path):
    """Delete every file in THIS user's dir except keep_path (retain-latest-for-retry).
    Scoped to one user so it can never touch another user's audio."""
    try:
        for f in os.listdir(user_dir):
            fp = os.path.join(user_dir, f)
            if fp != keep_path and os.path.isfile(fp):
                os.remove(fp)
    except Exception as e:
        print(f"WARNING: could not prune retained audio for user dir: {e}")

def cleanup_old_recordings():
    """Delete audio files older than 7 days from the recordings directory."""
    try:
        now = time.time()
        days_7_ago = now - (7 * 24 * 60 * 60)
        
        count = 0
        # Walk subdirs too — recordings now live under per-user subfolders (#8).
        for root, _dirs, files in os.walk(RECORDINGS_DIR):
            for filename in files:
                file_path = os.path.join(root, filename)
                if os.path.isfile(file_path):
                    file_time = os.path.getmtime(file_path)
                    if file_time < days_7_ago:
                        os.remove(file_path)
                        count += 1
        
        if count > 0:
            print(f"🧹 Cleaned up {count} old recordings.")
    except Exception as e:
        print(f"❌ Error cleaning up recordings: {e}")

# Global groq client (will be initialized with API key from request or config)
groq_client = None

def load_config():
    if os.path.exists(CONFIG_FILE):
        try:
            with open(CONFIG_FILE, 'r') as f:
                return json.load(f)
        except (json.JSONDecodeError, OSError) as e:
            # ASCII-only: this is the graceful-degradation path; an emoji here would
            # itself crash on a non-UTF-8 console and defeat BUG-09.
            print(f"WARNING: config.json unreadable ({e}); falling back to empty config")
    return {}

def save_config(config):
    with open(CONFIG_FILE, 'w') as f:
        json.dump(config, f, indent=2)

# ── Secret storage (BUG-17) ──────────────────────────────────────────────────
# Credentials live in the OS keychain (Windows Credential Manager / macOS Keychain
# / Linux SecretService) via `keyring`, NOT plaintext in config.json. If no keychain
# backend is available (e.g. headless Linux) we transparently fall back to
# config.json so the app never breaks. Non-secret settings (region, language, model
# ids, cognito ids, auth_mode, dynamodb_endpoint_url) always stay in config.json.
SECRET_SERVICE = 'Echo'
SECRET_KEYS = {
    'api_key', 'openai_api_key',
    'aws_access_key_id', 'aws_secret_access_key',
    'dynamodb_access_key_id', 'dynamodb_secret_access_key',
    'bedrock_api_key',
    'local_auth_secret',
}
_keyring_mod = None      # the keyring module once a backend is wired up
_keyring_ready = None    # tri-state: None=untried, True=usable, False=unavailable

def _keyring_available():
    """Wire up an EXPLICIT backend (entry-point auto-discovery is unreliable in a
    PyInstaller-frozen exe → 'No recommended backend') and probe it once. Cached."""
    global _keyring_mod, _keyring_ready
    if _keyring_ready is not None:
        return _keyring_ready
    try:
        import keyring
        if sys.platform == 'win32':
            from keyring.backends import Windows
            keyring.set_keyring(Windows.WinVaultKeyring())
        elif sys.platform == 'darwin':
            from keyring.backends import macOS
            keyring.set_keyring(macOS.Keyring())
        else:
            from keyring.backends import SecretService
            keyring.set_keyring(SecretService.Keyring())
        # Probe a sentinel so an unusable backend fails HERE, not mid-request.
        keyring.set_password(SECRET_SERVICE, '__probe__', 'ok')
        if keyring.get_password(SECRET_SERVICE, '__probe__') != 'ok':
            raise RuntimeError('keyring probe mismatch')
        keyring.delete_password(SECRET_SERVICE, '__probe__')
        _keyring_mod = keyring
        _keyring_ready = True
    except Exception as e:
        print(f"WARNING: OS keychain unavailable ({e}); secrets fall back to config.json")
        _keyring_ready = False
    return _keyring_ready

def get_secret(name):
    """Read a secret: keychain first, then config.json (covers the fallback path and
    the pre-migration window)."""
    if _keyring_available():
        try:
            v = _keyring_mod.get_password(SECRET_SERVICE, name)
            if v is not None:
                return v
        except Exception as e:
            print(f"WARNING: keychain read failed for {name} ({e})")
    return load_config().get(name)

def set_secret(name, value):
    """Store a secret in the keychain when possible (and strip any plaintext copy from
    config.json); otherwise persist to config.json."""
    if _keyring_available():
        try:
            _keyring_mod.set_password(SECRET_SERVICE, name, value)
            cfg = load_config()
            if name in cfg:
                cfg.pop(name, None)
                save_config(cfg)
            return
        except Exception as e:
            print(f"WARNING: keychain write failed for {name} ({e}); using config.json")
    cfg = load_config()
    cfg[name] = value
    save_config(cfg)

def migrate_secrets_to_keyring():
    """One-time: lift any plaintext secrets out of config.json into the keychain, then
    rewrite config.json without them. No-op when the keychain is unavailable."""
    if not _keyring_available():
        return
    cfg = load_config()
    changed = False
    for k in SECRET_KEYS:
        v = cfg.get(k)
        if v:
            try:
                _keyring_mod.set_password(SECRET_SERVICE, k, v)
                cfg.pop(k, None)
                changed = True
            except Exception as e:
                print(f"WARNING: could not migrate {k} to keychain ({e})")
    if changed:
        save_config(cfg)
        print("Migrated plaintext secrets from config.json into the OS keychain.")

def get_api_key():
    return get_secret('api_key')

def init_groq_client(api_key):
    global groq_client
    groq_client = Groq(api_key=api_key)

def load_history():
    if os.path.exists(HISTORY_FILE):
        try:
            with open(HISTORY_FILE, 'r') as f:
                return json.load(f)
        except (json.JSONDecodeError, OSError) as e:
            print(f"WARNING: transcription_history.json unreadable ({e}); falling back to empty history")
    return []

def save_history(history):
    with open(HISTORY_FILE, 'w') as f:
        json.dump(history, f, indent=2)

# ----- Config-driven settings (Phase 3) -----

def get_history_retention_days():
    """Days of transcription history to keep. 0 = keep forever (D5 / BUG-16)."""
    config = load_config()
    try:
        days = int(config.get('history_retention_days', DEFAULT_HISTORY_RETENTION_DAYS))
    except (TypeError, ValueError):
        return DEFAULT_HISTORY_RETENTION_DAYS
    return days if days >= 0 else DEFAULT_HISTORY_RETENTION_DAYS

def get_language():
    """Transcription language (ISO-639-1) or 'auto' to let Whisper detect (BUG-20)."""
    config = load_config()
    lang = config.get('language', DEFAULT_LANGUAGE)
    if not isinstance(lang, str) or not lang.strip():
        return DEFAULT_LANGUAGE
    return lang.strip()

def prune_history(history, retention_days):
    """Return (kept_entries, removed_count). Entries with an unparseable timestamp
    are kept so a single bad row never silently drops good data (corrupt-safe)."""
    if not isinstance(history, list) or retention_days <= 0:
        return history if isinstance(history, list) else [], 0
    cutoff = datetime.now() - timedelta(days=retention_days)
    kept, removed = [], 0
    for entry in history:
        ts = entry.get('timestamp') if isinstance(entry, dict) else None
        try:
            # Parse only the fixed YYYYMMDD_HHMMSS prefix so this tolerates both the
            # old 1-second timestamps and the new microsecond ones (..._%f), plus any
            # trailing data. Non-str/None raises here → caught → kept (corrupt-safe).
            entry_dt = datetime.strptime(ts[:15], "%Y%m%d_%H%M%S")
        except (TypeError, ValueError):
            kept.append(entry)
            continue
        if entry_dt >= cutoff:
            kept.append(entry)
        else:
            removed += 1
    return kept, removed

def cleanup_history():
    """Load, prune by configured retention, persist if anything changed, return kept."""
    history = load_history()
    pruned, removed = prune_history(history, get_history_retention_days())
    if removed > 0:
        save_history(pruned)
        print(f"🧹 Pruned {removed} history entries past retention.")
    return pruned

def validate_groq_key(api_key):
    """Make a real authenticated call so a bad key is actually rejected (BUG-08).
    Returns (ok, reason) where reason is 'invalid_key' | 'unreachable:<msg>' | None."""
    try:
        Groq(api_key=api_key).models.list()
        return True, None
    except AuthenticationError:
        return False, 'invalid_key'
    except APIConnectionError as e:
        return False, f'unreachable:{e}'
    except Exception as e:
        # Any other error (rate limit, unexpected) — don't claim the key is good
        return False, f'unreachable:{e}'

def validate_openai_key(api_key):
    """Validate an OpenAI key with a real call (GET /v1/models). Uses stdlib urllib
    so no extra dependency is needed. Same (ok, reason) contract as validate_groq_key (D4)."""
    import urllib.request, urllib.error
    req = urllib.request.Request(
        'https://api.openai.com/v1/models',
        headers={'Authorization': f'Bearer {api_key}'}
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            return (True, None) if resp.status == 200 else (False, f'unreachable:HTTP {resp.status}')
    except urllib.error.HTTPError as e:
        return (False, 'invalid_key') if e.code in (401, 403) else (False, f'unreachable:HTTP {e.code}')
    except Exception as e:
        return False, f'unreachable:{e}'

def validate_bedrock_creds(api_key, region):
    """Validate a Bedrock API key with a real signed call (bedrock list_foundation_models)
    via boto3. Same (ok, reason) contract (D4). Bedrock API keys are bearer tokens, not
    IAM access/secret key pairs - botocore auto-prefers bearer auth (sends
    Authorization: Bearer <token>) over SigV4 when AWS_BEARER_TOKEN_BEDROCK is set and no
    aws_access_key_id/aws_secret_access_key are passed to the client."""
    try:
        import boto3
        from botocore.config import Config
        from botocore.exceptions import ClientError
    except ImportError:
        return False, 'unreachable:boto3 not installed'
    prior = os.environ.get('AWS_BEARER_TOKEN_BEDROCK')
    os.environ['AWS_BEARER_TOKEN_BEDROCK'] = api_key
    try:
        client = boto3.client(
            'bedrock', region_name=region,
            config=Config(user_agent_extra=AWS_PRM_USER_AGENT)
        )
        client.list_foundation_models()
        return True, None
    except ClientError as e:
        code = e.response.get('Error', {}).get('Code', '')
        bad = {'UnrecognizedClientException', 'InvalidSignatureException',
               'InvalidClientTokenId', 'SignatureDoesNotMatch', 'AuthFailure'}
        return (False, 'invalid_key') if code in bad else (False, f'unreachable:{code or e}')
    except Exception as e:
        return False, f'unreachable:{e}'
    finally:
        if prior is None:
            os.environ.pop('AWS_BEARER_TOKEN_BEDROCK', None)
        else:
            os.environ['AWS_BEARER_TOKEN_BEDROCK'] = prior

# ── Cognito JWT auth ──────────────────────────────────────────────────────────

COGNITO_REGION      = os.environ.get('COGNITO_REGION', '')
COGNITO_USER_POOL_ID = os.environ.get('COGNITO_USER_POOL_ID', '')
COGNITO_APP_CLIENT_ID = os.environ.get('COGNITO_APP_CLIENT_ID', '')

_jwks_cache = {'keys': None, 'fetched_at': 0}

def _get_jwks():
    if time.time() - _jwks_cache['fetched_at'] < 3600 and _jwks_cache['keys']:
        return _jwks_cache['keys']
    import urllib.request
    url = (f'https://cognito-idp.{COGNITO_REGION}.amazonaws.com'
           f'/{COGNITO_USER_POOL_ID}/.well-known/jwks.json')
    with urllib.request.urlopen(url, timeout=5) as resp:
        _jwks_cache['keys'] = json.loads(resp.read())['keys']
        _jwks_cache['fetched_at'] = time.time()
    return _jwks_cache['keys']

# ── Local-only auth (DEV/TEST) ────────────────────────────────────────────────
# A throwaway email/password login backed by DynamoDB Local, so the full login UX
# can be exercised on a dev machine WITHOUT AWS Cognito. Active ONLY when
# config.json has "auth_mode": "local" and Cognito is not configured. Replaced by
# Cognito automatically once cognito_* keys are present — NOT for production.
import hmac as _hmac, hashlib as _hashlib, base64 as _b64
import random as _random
import secrets as _secrets

# In-memory OTP store: {email: {'otp': str, 'expires': float}}
_otp_store: dict = {}

def local_auth_enabled():
    return (load_config().get('auth_mode') or '').lower() == 'local' and not COGNITO_USER_POOL_ID

_local_secret_cache = None

def _local_secret():
    """Per-install HS256 signing secret for local-auth tokens. Read from the secret
    store; if absent, generate a strong random one and persist it. NEVER fall back to a
    known constant (that would let anyone forge tokens). An explicitly-set
    'local_auth_secret' still overrides via get_secret()."""
    global _local_secret_cache
    if _local_secret_cache:
        return _local_secret_cache
    s = get_secret('local_auth_secret')
    if not s:
        s = _secrets.token_urlsafe(48)        # ~64 chars, cryptographically strong
        set_secret('local_auth_secret', s)    # → OS keychain (#4), or plaintext fallback
        print('Generated a new per-install local-auth signing secret.')
    _local_secret_cache = s
    return s

def _b64url_encode(raw):
    return _b64.urlsafe_b64encode(raw).rstrip(b'=').decode()

def _b64url_decode(s):
    return _b64.urlsafe_b64decode(s + '=' * (-len(s) % 4))

def make_local_token(email, hours=24 * 7):
    """Build a small HS256 JWT the existing token plumbing already understands."""
    header  = _b64url_encode(json.dumps({'alg': 'HS256', 'typ': 'JWT'}).encode())
    payload = _b64url_encode(json.dumps({'sub': email, 'email': email,
                                         'exp': int(time.time()) + hours * 3600}).encode())
    signing_input = f'{header}.{payload}'.encode()
    sig = _b64url_encode(_hmac.new(_local_secret().encode(), signing_input, _hashlib.sha256).digest())
    return f'{header}.{payload}.{sig}'

def verify_local_token(token):
    try:
        header, payload, sig = token.split('.')
        signing_input = f'{header}.{payload}'.encode()
        expected = _b64url_encode(_hmac.new(_local_secret().encode(), signing_input, _hashlib.sha256).digest())
        if not _hmac.compare_digest(sig, expected):
            return None
        data = json.loads(_b64url_decode(payload))
        if data.get('exp', 0) < time.time():
            return None
        return data.get('sub')
    except Exception:
        return None

def require_auth(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        # 1) Production: validate a real Cognito JWT.
        if COGNITO_USER_POOL_ID:
            token = request.headers.get('Authorization', '').removeprefix('Bearer ').strip()
            if not token:
                return jsonify({'error': 'Unauthorized'}), 401
            try:
                from jose import jwt, JWTError
                claims = jwt.decode(token, _get_jwks(), algorithms=['RS256'],
                                    audience=COGNITO_APP_CLIENT_ID)
                g.user_id = claims['sub']
            except Exception:
                return jsonify({'error': 'Unauthorized'}), 401
            return f(*args, **kwargs)
        # 2) Local test: validate our throwaway HS256 token.
        if local_auth_enabled():
            token = request.headers.get('Authorization', '').removeprefix('Bearer ').strip()
            email = verify_local_token(token)
            if not email:
                return jsonify({'error': 'Unauthorized'}), 401
            g.user_id = email
            return f(*args, **kwargs)
        # 3) Dev bypass: no auth configured at all.
        g.user_id = 'dev-user'
        return f(*args, **kwargs)
    return decorated

# ── DynamoDB ─────────────────────────────────────────────────────────────────

_dynamo = None

def get_dynamo():
    global _dynamo
    if _dynamo is None:
        cfg = load_config()
        endpoint = cfg.get('dynamodb_endpoint_url')  # e.g. http://localhost:8000 for DynamoDB Local
        key_id = get_secret('dynamodb_access_key_id') or get_secret('aws_access_key_id')
        secret  = get_secret('dynamodb_secret_access_key') or get_secret('aws_secret_access_key')
        region  = cfg.get('aws_region', 'us-east-1')
        import boto3
        from botocore.config import Config
        # Fail FAST so an unreachable DB (e.g. dynalite not running) can never freeze
        # transcription/history — short timeouts + no retries. DB writes are best-effort.
        bcfg = Config(connect_timeout=1, read_timeout=2, retries={'mode': 'standard', 'max_attempts': 1})
        if endpoint:
            # LOCAL TEST MODE — DynamoDB Local accepts dummy credentials and a custom
            # endpoint. Lets the whole DB layer be exercised on your PC, no AWS account.
            _dynamo = boto3.resource('dynamodb',
                region_name=region,
                endpoint_url=endpoint,
                aws_access_key_id=key_id or 'local',
                aws_secret_access_key=secret or 'local',
                config=bcfg)
        elif key_id and secret:
            _dynamo = boto3.resource('dynamodb',
                region_name=region,
                aws_access_key_id=key_id,
                aws_secret_access_key=secret,
                config=bcfg)
        else:
            return None  # unconfigured → DB layer stays dormant (v1 behaviour)
    return _dynamo

def _reset_dynamo_cache():
    """Drop the cached DynamoDB resource so the next get_dynamo() rebuilds it with
    current credentials. Call after any runtime credential/region change."""
    global _dynamo
    _dynamo = None

def _run_async(fn):
    """Run a best-effort DB write in the background so it NEVER blocks the request
    (a slow/unreachable DB must not delay transcription)."""
    threading.Thread(target=fn, daemon=True).start()

def dynamo_put_history(user_id, entry):
    def _work():
        try:
            db = get_dynamo()
            if db is None:
                return
            db.Table('whisperflow-history').put_item(Item={
                'userId':    user_id,
                'timestamp': entry['timestamp'],
                'text':      entry.get('text', ''),
                'model':     entry.get('model', ''),
            })
        except Exception as e:
            print(f'[dynamo] put_history error: {e}')
    _run_async(_work)

def dynamo_fetch_history(user_id, days=30):
    try:
        db = get_dynamo()
        if db is None:
            return []
        from boto3.dynamodb.conditions import Key
        cutoff = (datetime.now() - timedelta(days=days)).strftime('%Y%m%d_%H%M%S')
        resp = db.Table('whisperflow-history').query(
            KeyConditionExpression=Key('userId').eq(user_id) & Key('timestamp').gte(cutoff),
            ScanIndexForward=False,
            Limit=200,
        )
        return resp.get('Items', [])
    except Exception as e:
        print(f'[dynamo] fetch_history error: {e}')
        return []

def dynamo_log_event(user_id, event, meta=None):
    """Best-effort usage/analytics event → whisperflow-events. Fire-and-forget so it
    never blocks the request; no-op when DynamoDB is unconfigured (stays DORMANT)."""
    def _work():
        try:
            db = get_dynamo()
            if db is None:
                return
            db.Table('whisperflow-events').put_item(Item={
                'userId':    user_id,
                # microsecond precision so rapid events don't collide on the sort key
                'timestamp': datetime.now().strftime('%Y%m%d_%H%M%S_%f'),
                'event':     event,
                'meta':      meta or {},
            })
        except Exception as e:
            print(f'[dynamo] log_event error: {e}')
    _run_async(_work)

# ── Bedrock grammar correction ────────────────────────────────────────────────

# System instruction shared by every grammar provider. Lives in the SYSTEM role
# (not the user turn) so the model follows it reliably and stops emitting preambles
# like "Here is the corrected text:". Examples are intentionally UNquoted so the
# model doesn't learn to wrap its output in quotes.
_GRAMMAR_SYSTEM = (
    'You are a transcription proofreader. Your ONLY job is to fix mechanical '
    'errors in a speech-to-text transcript while preserving the speaker\'s exact '
    'words.\n\n'
    'HARD RULES — follow these above everything else:\n'
    '- Keep the speaker\'s original words, phrasing, and sentence structure. Do NOT '
    'rephrase, reword, restructure, summarize, expand, or "improve" anything.\n'
    '- Change ONLY: spelling, capitalization, punctuation, and obvious '
    'speech-to-text mishears (e.g. "their" vs "there"). Nothing else.\n'
    '- Never add information, opinions, or detail the speaker did not say.\n'
    '- Never remove or shorten content. If unsure, leave it exactly as-is.\n'
    '- If the transcript is already correct, return it UNCHANGED.\n\n'
    'FORMATTING:\n'
    '- If the speaker is clearly dictating a list (e.g. "first... second...", or '
    'several distinct items/steps), put each item on its own line starting with '
    '"- ", using THE SPEAKER\'S OWN WORDS for each item. Do not condense them.\n'
    '- Otherwise keep it as normal prose. Never bulletize a single statement.\n\n'
    'OUTPUT: Return ONLY the corrected transcript itself — no preamble, no '
    '"Here is...", no "Note:", no explanation, and no surrounding quotation marks.\n\n'
    'Examples:\n'
    'Input:  i went to the store their were no apples so i bought oranges instead\n'
    'Output: I went to the store. There were no apples, so I bought oranges instead.\n\n'
    'Input:  we need three things first the report second the budget and third the slides\n'
    'Output: We need three things:\n'
    '- First, the report\n'
    '- Second, the budget\n'
    '- Third, the slides'
)

# Conservative net for any preamble the model still emits despite the system rule.
# Every branch requires a correction-meta cue, so real dictation ("Sure, here is my
# plan:", "Note: buy milk") is NEVER stripped.
_PREAMBLE_RE = re.compile(
    r'^\s*(?:'
    r'notes?\s*:[^\n]*\b(?:correct|transcript|spell|punctuat|grammar|capitaliz|made|chang|fix|here)[^\n]*'
    r'|(?:sure|okay|ok|certainly|of course)?[,!.\s]*here(?:\'s| is)?[^\n]*correct[^\n]*:'
    r'|(?:the\s+)?correct(?:ed)?\s+(?:text|version|transcript)[^\n]*:'
    r')\s*\n?', re.IGNORECASE)

def _strip_llm_preamble(text):
    """Strip ONE leading line of LLM meta-commentary if present (conservative)."""
    if not text:
        return text
    return _PREAMBLE_RE.sub('', text, count=1).strip()

def grammar_correction_enabled():
    """Whether grammar correction should run at all.

    Config key: 'grammar_correction_enabled' (bool, default True). When it is
    absent — i.e. a config.json written by <= v1.2.18 — derive it from the legacy
    'grammar_provider' string so upgrading users keep the behaviour they had:
    they'd explicitly turned it off, or they hadn't."""
    cfg = load_config()
    if 'grammar_correction_enabled' in cfg:
        return bool(cfg['grammar_correction_enabled'])
    legacy = (cfg.get('grammar_provider') or '').lower().strip()
    return legacy not in ('none', 'off', 'disabled')

def correct_text(text):
    """Grammar/structuring correction. AWS Bedrock is the ONLY engine.

    Groq is deliberately not a fallback here — it is the speech-to-text engine and
    nothing else. If no Bedrock API key is configured, the transcript is returned
    verbatim rather than corrected by some other provider. Any failure returns the
    original text unchanged; a dictation is never lost to a grammar-pass error."""
    if not text or not text.strip():
        return text
    if not grammar_correction_enabled():
        return text
    return correct_text_with_bedrock(text)

def correct_text_with_bedrock(text):
    try:
        cfg = load_config()
        model_id = cfg.get('bedrock_llm_model_id', 'amazon.nova-lite-v1:0')
        api_key  = get_secret('bedrock_api_key')
        region   = cfg.get('aws_region', 'us-east-1')
        if not api_key:
            # Enabled but unconfigured: pass the transcript through untouched.
            # Logged (not silent) so this no-op is diagnosable from the log file.
            print('[bedrock] grammar correction skipped: no Bedrock API key configured')
            return text
        import boto3
        from botocore.config import Config
        # Bedrock API keys are bearer tokens - botocore auto-prefers bearer auth over
        # SigV4 when AWS_BEARER_TOKEN_BEDROCK is set and no access/secret key is passed.
        prior = os.environ.get('AWS_BEARER_TOKEN_BEDROCK')
        os.environ['AWS_BEARER_TOKEN_BEDROCK'] = api_key
        try:
            client = boto3.client('bedrock-runtime',
                region_name=region,
                config=Config(user_agent_extra=AWS_PRM_USER_AGENT))
            # Converse API: same request/response shape across every Bedrock model
            # family (Nova, Llama, Mistral, Anthropic, ...) - so swapping models is
            # a config value change (bedrock_llm_model_id), never a code change.
            resp = client.converse(
                modelId=model_id,
                system=[{'text': _GRAMMAR_SYSTEM}],
                messages=[{'role': 'user', 'content': [{'text': text}]}],
                inferenceConfig={'maxTokens': 4096, 'temperature': 0},
            )
            corrected = resp['output']['message']['content'][0]['text'].strip()
            corrected = _strip_llm_preamble(corrected)
            print('[bedrock] grammar correction applied')
            return corrected
        finally:
            if prior is None:
                os.environ.pop('AWS_BEARER_TOKEN_BEDROCK', None)
            else:
                os.environ['AWS_BEARER_TOKEN_BEDROCK'] = prior
    except Exception as e:
        print(f'[bedrock] grammar correction failed, using original: {e}')
        return text

# ── Shared transcription helpers ────────────────────────────────────────────────
# Prompt + kwargs builder shared by /api/transcribe and /api/retry so the audio
# pipeline stays identical between a fresh capture and a retry of the last one.
TRANSCRIBE_PROMPT = ("Technical discussion. Preserve terms: AWS, Google, API, shadcn, React, "
                     "TypeScript, SOW, SDK, UI/UX. Format lists as bullet points or numbers. "
                     "Clear structure with proper punctuation.")

def build_transcribe_kwargs(filename, file_content, model):
    kwargs = {
        "file": (filename, file_content),
        "model": model,
        "temperature": 0.0,
        "response_format": "verbose_json",
        "timestamp_granularities": ["segment"],
        "prompt": TRANSCRIBE_PROMPT,
    }
    language = get_language()
    if language and language.lower() != "auto":
        kwargs["language"] = language  # better accuracy + latency (BUG-20)
    return kwargs

# Retain only the most recent recording on disk so the user can retry transcription
# without re-recording. Previous retained file is dropped when a new one arrives.
_last_recording = {}  # keyed by user_id → {'path':..., 'model':...} so retry is per-user (#8)

# ─────────────────────────────────────────────────────────────────────────────

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/api/auth-config', methods=['GET'])
def auth_config():
    """Public Cognito IDs for the renderer's email/password login. Pool/client IDs
    are not secrets; they ship in every client app. No secrets are returned here."""
    mode = 'cognito' if COGNITO_USER_POOL_ID else ('local' if local_auth_enabled() else 'dev')
    return jsonify({
        'configured':   bool(COGNITO_USER_POOL_ID),
        'mode':         mode,   # cognito | local | dev — tells the login screen what to render
        'region':       COGNITO_REGION,
        'user_pool_id': COGNITO_USER_POOL_ID,
        'client_id':    COGNITO_APP_CLIENT_ID,
    })

@app.route('/api/local-auth/register', methods=['POST'])
def local_register():
    """Create a local test account in DynamoDB Local. Local-mode only."""
    if not local_auth_enabled():
        return jsonify({'error': 'Local auth is not enabled'}), 400
    data = request.json or {}
    email = (data.get('email') or '').strip().lower()
    password = data.get('password') or ''
    if not email or not password:
        return jsonify({'error': 'Email and password are required'}), 400
    if len(password) < 6:
        return jsonify({'error': 'Password must be at least 6 characters'}), 400
    db = get_dynamo()
    if db is None:
        return jsonify({'error': 'Local DB not reachable — start dynalite and set dynamodb_endpoint_url'}), 503
    from werkzeug.security import generate_password_hash
    try:
        tbl = db.Table('whisperflow-users')
        if tbl.get_item(Key={'email': email}).get('Item'):
            return jsonify({'error': 'An account with that email already exists'}), 409
        tbl.put_item(Item={'email': email,
                           'password_hash': generate_password_hash(password),
                           'created': datetime.now().strftime('%Y%m%d_%H%M%S')})
    except Exception as e:
        return jsonify({'error': str(e)}), 500
    dynamo_log_event(email, 'register', {'mode': 'local'})
    return jsonify({'success': True, 'token': make_local_token(email), 'email': email})

@app.route('/api/local-auth/login', methods=['POST'])
def local_login():
    """Authenticate against a local test account. Local-mode only."""
    if not local_auth_enabled():
        return jsonify({'error': 'Local auth is not enabled'}), 400
    data = request.json or {}
    email = (data.get('email') or '').strip().lower()
    password = data.get('password') or ''
    db = get_dynamo()
    if db is None:
        return jsonify({'error': 'Local DB not reachable — start dynalite and set dynamodb_endpoint_url'}), 503
    from werkzeug.security import check_password_hash
    try:
        item = db.Table('whisperflow-users').get_item(Key={'email': email}).get('Item')
    except Exception as e:
        return jsonify({'error': str(e)}), 500
    if not item or not check_password_hash(item.get('password_hash', ''), password):
        return jsonify({'error': 'Invalid email or password'}), 401
    dynamo_log_event(email, 'login', {'mode': 'local'})
    return jsonify({'success': True, 'token': make_local_token(email), 'email': email})

@app.route('/api/local-auth/send-otp', methods=['POST'])
def local_send_otp():
    """Generate a 6-digit OTP and print it to console (local test mode)."""
    if not local_auth_enabled():
        return jsonify({'error': 'Local auth is not enabled'}), 400
    data = request.json or {}
    email = (data.get('email') or '').strip().lower()
    if not email or '@' not in email:
        return jsonify({'error': 'Valid email required'}), 400
    otp = str(_random.randint(100000, 999999))
    _otp_store[email] = {'otp': otp, 'expires': time.time() + 300}  # 5 min
    print(f'[Echo OTP] Code for {email}: {otp}  (expires in 5 min)', flush=True)
    return jsonify({'success': True,
                    'message': 'OTP generated. Check the Echo console/log for your code (local mode).'})

@app.route('/api/local-auth/verify-otp', methods=['POST'])
def local_verify_otp():
    """Verify OTP and issue a JWT. Creates user record on first login."""
    if not local_auth_enabled():
        return jsonify({'error': 'Local auth is not enabled'}), 400
    data = request.json or {}
    email = (data.get('email') or '').strip().lower()
    otp = (data.get('otp') or '').strip()
    stored = _otp_store.get(email)
    if not stored:
        return jsonify({'error': 'No OTP sent for this email. Request a new one.'}), 400
    if time.time() > stored['expires']:
        _otp_store.pop(email, None)
        return jsonify({'error': 'OTP expired. Request a new one.'}), 400
    if stored['otp'] != otp:
        return jsonify({'error': 'Invalid OTP. Try again.'}), 400
    _otp_store.pop(email, None)
    # Create user if they don't exist yet (OTP = registration + login in one step).
    try:
        db = get_dynamo()
        if db:
            from boto3.dynamodb.conditions import Attr
            db.Table('whisperflow-users').put_item(
                Item={'email': email, 'created': datetime.now().strftime('%Y%m%d_%H%M%S')},
                ConditionExpression=Attr('email').not_exists()
            )
    except Exception:
        pass  # User already exists, or DB unavailable — both are fine
    dynamo_log_event(email, 'otp_login', {'mode': 'local'})
    return jsonify({'success': True, 'token': make_local_token(email), 'email': email})

@app.route('/api/history', methods=['GET'])
@require_auth
def get_history():
    history = cleanup_history()
    # Merge cloud history (dedup by timestamp, cloud fills gaps across devices)
    cloud = dynamo_fetch_history(g.user_id, get_history_retention_days() or 30)
    if cloud:
        local_ts = {e['timestamp'] for e in history if isinstance(e, dict)}
        for item in cloud:
            if item.get('timestamp') not in local_ts:
                history.append({'timestamp': item['timestamp'],
                                'text': item.get('text', ''),
                                'model': item.get('model', ''),
                                'filename': None})
        history.sort(key=lambda e: e.get('timestamp', ''), reverse=True)
    return jsonify(history)

@app.route('/api/settings/api-key', methods=['POST'])
def set_api_key():
    try:
        data = request.get_json()
        api_key = data.get('api_key', '').strip()
        
        if not api_key:
            return jsonify({'error': 'API key is required'}), 400

        # BUG-08: actually authenticate the key against Groq before saving.
        # The old code only constructed the client (which never calls the API),
        # so any garbage string was accepted.
        ok, reason = validate_groq_key(api_key)
        if not ok:
            if reason == 'invalid_key':
                return jsonify({'error': 'Invalid API key'}), 400
            # Couldn't reach Groq — don't save an unverified key
            return jsonify({'error': 'Could not validate key — Groq is unreachable. Check your connection and try again.'}), 502

        # Save API key (OS keychain when available — BUG-17)
        set_secret('api_key', api_key)
        init_groq_client(api_key)
        
        return jsonify({'success': True})
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/settings/api-key', methods=['GET'])
def get_api_key_status():
    api_key = get_api_key()
    return jsonify({'has_api_key': bool(api_key)})

@app.route('/api/settings/retention', methods=['GET'])
def get_retention():
    return jsonify({'retention_days': get_history_retention_days()})

@app.route('/api/settings/retention', methods=['POST'])
def set_retention():
    try:
        data = request.get_json() or {}
        try:
            days = int(data.get('retention_days'))
        except (TypeError, ValueError):
            return jsonify({'error': 'retention_days must be an integer (0 = keep forever)'}), 400
        if days < 0:
            return jsonify({'error': 'retention_days cannot be negative'}), 400
        config = load_config()
        config['history_retention_days'] = days
        save_config(config)
        cleanup_history()  # apply the new policy immediately
        return jsonify({'success': True, 'retention_days': days})
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/settings/language', methods=['GET'])
def get_language_setting():
    return jsonify({'language': get_language()})

@app.route('/api/settings/language', methods=['POST'])
def set_language_setting():
    try:
        data = request.get_json() or {}
        lang = (data.get('language') or '').strip()
        if not lang:
            return jsonify({'error': 'language is required (ISO-639-1 code, or "auto")'}), 400
        if lang.lower() != 'auto' and not (2 <= len(lang) <= 5):
            return jsonify({'error': 'language must be a 2-5 char code or "auto"'}), 400
        config = load_config()
        config['language'] = lang
        save_config(config)
        return jsonify({'success': True, 'language': lang})
    except Exception as e:
        return jsonify({'error': str(e)}), 500

# ----- Multi-provider settings panel (D4) -----
# Keys are stored server-side only (credential-proxy constraint) and NEVER returned
# to the renderer — the UI only learns whether a provider is configured.

def storage_warning():
    """Tell the UI where secrets actually live, so the panel reflects reality (BUG-17)."""
    if _keyring_available():
        return 'Credentials are stored securely in your OS keychain.'
    return ('Keys are stored unencrypted in config.json on this device '
            '(no OS keychain backend available).')

@app.route('/api/feedback', methods=['POST'])
@require_auth
def submit_feedback():
    data = request.json or {}
    entry = {
        'userId':           g.user_id,
        # microsecond precision so two ratings in the same second don't collide on
        # the (userId, timestamp) sort key and overwrite each other
        'timestamp':        datetime.now().strftime('%Y%m%d_%H%M%S_%f'),
        'rating':           data.get('rating'),
        'comment':          data.get('comment', ''),
        'transcription_id': data.get('transcription_id', ''),
    }
    try:
        db = get_dynamo()
        if db is None:
            return jsonify({'success': False, 'error': 'DynamoDB not configured'}), 503
        db.Table('whisperflow-feedback').put_item(Item=entry)
        dynamo_log_event(g.user_id, 'feedback', {'rating': data.get('rating')})
        return jsonify({'success': True})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500

def _mask_key(v):
    """Safe preview of a stored key: first 5 + last 5 chars only. Never returns the
    full secret (the full value stays server-side per the credential-proxy rule)."""
    if not v:
        return ''
    return (v[:5] + '…' + v[-5:]) if len(v) > 12 else '•••••'

@app.route('/api/settings', methods=['GET'])
def get_settings():
    config = load_config()
    groq_key    = get_secret('api_key')
    openai_key  = get_secret('openai_api_key')
    bedrock_key = get_secret('bedrock_api_key')
    return jsonify({
        'providers': {
            'groq':    {'configured': bool(groq_key),
                        'preview': _mask_key(groq_key)},
            'openai':  {'configured': bool(openai_key),
                        'preview': _mask_key(openai_key)},
            'bedrock': {
                'configured': bool(bedrock_key),
                'preview': _mask_key(bedrock_key),
            },
        },
        'language': get_language(),
        'retention_days': get_history_retention_days(),
        'active_transcription_provider': 'groq',  # Groq remains the engine (audio pipeline unchanged)
        # Grammar correction is Bedrock-only. 'enabled' is the user's toggle;
        # 'available' says whether a Bedrock key exists to actually run it.
        'grammar_correction_enabled': grammar_correction_enabled(),
        'grammar_available': bool(bedrock_key),
        'storage_warning': storage_warning(),
    })

@app.route('/api/settings/grammar-correction', methods=['POST'])
def set_grammar_correction():
    """Enable/disable grammar correction. It runs exclusively on AWS Bedrock and
    bills to the user's own AWS account, so it must remain switchable off."""
    data = request.get_json(silent=True) or {}
    if 'enabled' not in data or not isinstance(data['enabled'], bool):
        return jsonify({'success': False, 'error': "'enabled' must be a boolean"}), 400
    config = load_config()
    config['grammar_correction_enabled'] = data['enabled']
    config.pop('grammar_provider', None)   # retire the legacy key once migrated
    save_config(config)
    return jsonify({'success': True})

def _test_result(ok, reason):
    if ok:
        return jsonify({'success': True})
    if reason == 'invalid_key':
        return jsonify({'success': False, 'error': 'Invalid credentials'})
    detail = reason.split(':', 1)[-1] if reason else 'unknown error'
    return jsonify({'success': False, 'error': f'Could not connect: {detail}'})

@app.route('/api/settings/test', methods=['POST'])
def test_connection():
    """Validate credentials WITHOUT saving them (the 'Test Connection' button).
    Falls back to saved creds if the body omits them."""
    data = request.get_json() or {}
    provider = (data.get('provider') or '').lower()
    config = load_config()
    if provider == 'groq':
        key = (data.get('api_key') or get_secret('api_key') or '').strip()
        if not key:
            return jsonify({'success': False, 'error': 'No Groq key provided'}), 400
        return _test_result(*validate_groq_key(key))
    if provider == 'openai':
        key = (data.get('api_key') or get_secret('openai_api_key') or '').strip()
        if not key:
            return jsonify({'success': False, 'error': 'No OpenAI key provided'}), 400
        return _test_result(*validate_openai_key(key))
    if provider == 'bedrock':
        key = (data.get('bedrock_api_key') or get_secret('bedrock_api_key') or '').strip()
        rg = config.get('aws_region', 'us-east-1')
        if not key:
            return jsonify({'success': False, 'error': 'Bedrock API key required'}), 400
        return _test_result(*validate_bedrock_creds(key, rg))
    return jsonify({'success': False, 'error': 'Unknown provider'}), 400

@app.route('/api/settings/openai-key', methods=['POST'])
def set_openai_key():
    try:
        data = request.get_json() or {}
        key = (data.get('api_key') or '').strip()
        if not key:
            return jsonify({'error': 'API key is required'}), 400
        ok, reason = validate_openai_key(key)
        if not ok:
            if reason == 'invalid_key':
                return jsonify({'error': 'Invalid API key'}), 400
            return jsonify({'error': 'Could not validate key — OpenAI is unreachable.'}), 502
        set_secret('openai_api_key', key)
        return jsonify({'success': True})
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/settings/bedrock', methods=['POST'])
def set_bedrock_creds():
    try:
        data = request.get_json() or {}
        key = (data.get('bedrock_api_key') or '').strip()
        if not key:
            return jsonify({'error': 'Bedrock API key is required'}), 400
        rg = load_config().get('aws_region', 'us-east-1')
        ok, reason = validate_bedrock_creds(key, rg)
        if not ok:
            if reason == 'invalid_key':
                return jsonify({'error': 'Invalid Bedrock API key'}), 400
            detail = reason.split(':', 1)[-1] if reason else 'unreachable'
            return jsonify({'error': f'Could not validate key — {detail}'}), 502
        set_secret('bedrock_api_key', key)
        return jsonify({'success': True})
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/paste', methods=['POST'])
@require_auth
def do_paste():
    if sys.platform != 'win32':
        return jsonify({'success': False, 'error': 'Windows only'})
    try:
        import ctypes
        time.sleep(0.15)
        VK_CONTROL = 0x11
        VK_V = 0x56
        KEYEVENTF_KEYUP = 0x0002
        ctypes.windll.user32.keybd_event(VK_CONTROL, 0, 0, 0)
        ctypes.windll.user32.keybd_event(VK_V, 0, 0, 0)
        ctypes.windll.user32.keybd_event(VK_V, 0, KEYEVENTF_KEYUP, 0)
        ctypes.windll.user32.keybd_event(VK_CONTROL, 0, KEYEVENTF_KEYUP, 0)
        return jsonify({'success': True})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)})

@app.route('/api/transcribe', methods=['POST'])
@require_auth
def transcribe():
    try:
        # Run cleanup periodically on transcription requests
        cleanup_old_recordings()
        
        api_key = get_api_key()
        if not api_key:
            return jsonify({'error': 'API key not set. Please configure it in settings.'}), 400
        
        if not groq_client:
            init_groq_client(api_key)
        
        if 'audio' not in request.files:
            return jsonify({'error': 'No audio file provided'}), 400
        
        audio_file = request.files['audio']
        model = request.form.get('model', 'whisper-large-v3')
        
        # ═══════════════════════════════════════════════════════════════════════════
        # DIAGNOSTIC LOG #1: Original uploaded filename
        # ═══════════════════════════════════════════════════════════════════════════
        print("=" * 80)
        print("🔍 TRANSCRIPTION PIPELINE DIAGNOSTIC")
        print("=" * 80)
        print(f"[1] Original uploaded filename: {audio_file.filename}")
        
        # Generate filename - detect file type from the uploaded filename.
        # Microsecond precision so two transcriptions in the same second get distinct
        # history rows (and the (userId, timestamp) cloud sort key doesn't overwrite).
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S_%f")
        original_filename = audio_file.filename or 'recording.webm'
        
        # Determine file extension based on uploaded file
        if original_filename.endswith('.wav'):
            ext = 'wav'
        elif original_filename.endswith('.webm'):
            ext = 'webm'
        else:
            # Default to webm for browser recordings, wav for background recordings
            ext = 'wav' if 'wav' in original_filename.lower() else 'webm'
        
        filename = os.path.join(_user_recordings_dir(g.user_id), f"recording_{timestamp}.{ext}")
        
        # ═══════════════════════════════════════════════════════════════════════════
        # DIAGNOSTIC LOG #2: Saved filename on disk
        # ═══════════════════════════════════════════════════════════════════════════
        print(f"[2] Saved filename on disk: {filename}")
        
        # ═══════════════════════════════════════════════════════════════════════════
        # DIAGNOSTIC LOG #3: MIME type from Flask
        # ═══════════════════════════════════════════════════════════════════════════
        print(f"[3] MIME type received from Flask: {audio_file.content_type}")
        
        # Save audio file
        audio_file.save(filename)
        
        # Verify file was saved and get size
        file_size = os.path.getsize(filename)
        
        # ═══════════════════════════════════════════════════════════════════════════
        # DIAGNOSTIC LOG #4: File size
        # ═══════════════════════════════════════════════════════════════════════════
        print(f"[4] File size: {file_size} bytes ({file_size / (1024 * 1024):.2f} MB)")
        
        # Transcribe with best practices
        with open(filename, "rb") as file:
            file_content = file.read()
            file_size_mb = len(file_content) / (1024 * 1024)
            
            # ═══════════════════════════════════════════════════════════════════════════
            # DIAGNOSTIC LOG #5: First 16 bytes in hexadecimal
            # ═══════════════════════════════════════════════════════════════════════════
            if len(file_content) >= 16:
                header_hex = ' '.join(f'{b:02x}' for b in file_content[:16])
                header_ascii = ''.join(chr(b) if 32 <= b < 127 else '.' for b in file_content[:16])
                print(f"[5] First 16 bytes (hex): {header_hex}")
                print(f"    First 16 bytes (ascii): {header_ascii}")
            
            # Log first few bytes to verify file format
            if len(file_content) >= 12:
                header = file_content[:12]
                print(f"📋 File header (first 12 bytes): {header}")
                if header[:4] == b'RIFF' and header[8:12] == b'WAVE':
                    print("✅ Valid WAV file detected")
                elif header[:4] == b'\x1a\x45\xdf\xa3':
                    print("✅ Valid WebM file detected")
                else:
                    print(f"⚠️ Unknown file format, header: {header[:4]}")
            
            # BUG-20: language is configurable (defaults to "en"). "auto" omits the
            # param so Whisper auto-detects. Audio handling itself is unchanged.
            transcribe_kwargs = build_transcribe_kwargs(filename, file_content, model)
            
            # ═══════════════════════════════════════════════════════════════════════════
            # DIAGNOSTIC LOG #6: Groq API call parameters
            # ═══════════════════════════════════════════════════════════════════════════
            print("=" * 80)
            print("📡 GROQ API CALL")
            print("=" * 80)
            print(f"[6] Groq API parameters:")
            print(f"    - model: {transcribe_kwargs.get('model')}")
            print(f"    - filename: {transcribe_kwargs['file'][0]}")
            print(f"    - extension: {os.path.splitext(transcribe_kwargs['file'][0])[1]}")
            print(f"    - language: {transcribe_kwargs.get('language', 'auto (not specified)')}")
            print(f"    - response_format: {transcribe_kwargs.get('response_format')}")
            print(f"    - temperature: {transcribe_kwargs.get('temperature')}")
            print(f"    - timestamp_granularities: {transcribe_kwargs.get('timestamp_granularities')}")
            
            transcription = groq_client.audio.transcriptions.create(**transcribe_kwargs)
        
        # ═══════════════════════════════════════════════════════════════════════════
        # DIAGNOSTIC LOG #7: Groq API response
        # ═══════════════════════════════════════════════════════════════════════════
        print("=" * 80)
        print("📥 GROQ API RESPONSE")
        print("=" * 80)
        
        # Extract text from response
        text = transcription.text if hasattr(transcription, 'text') else ""
        
        print(f"[7] Groq API response:")
        print(f"    - transcription.text: '{text}'")
        print(f"    - transcription.text length: {len(text)} characters")
        
        if hasattr(transcription, 'duration'):
            print(f"    - transcription.duration: {transcription.duration}s")
        else:
            print(f"    - transcription.duration: (not available)")
        
        if hasattr(transcription, 'segments') and transcription.segments:
            print(f"    - number of segments: {len(transcription.segments)}")
            for idx, segment in enumerate(transcription.segments, 1):
                seg_text = getattr(segment, 'text', '(no text)')
                seg_start = getattr(segment, 'start', '?')
                seg_end = getattr(segment, 'end', '?')
                print(f"      Segment {idx} [{seg_start}-{seg_end}s]: '{seg_text}'")
        else:
            print(f"    - segments: (not available)")
        
        # ═══════════════════════════════════════════════════════════════════════════
        # DIAGNOSTIC LOG #8: After grammar correction
        # ═══════════════════════════════════════════════════════════════════════════
        print("=" * 80)
        print("✏️ GRAMMAR CORRECTION")
        print("=" * 80)
        print(f"[8] Text before correction: '{text}'")
        
        text = correct_text(text)
        
        print(f"[8] Text after correction: '{text}'")
        print(f"    - corrected text length: {len(text)} characters")

        # Log transcription details for debugging
        print(f"✓ Transcription completed: {len(text)} characters")
        if hasattr(transcription, 'duration'):
            print(f"  Audio duration: {transcription.duration}s")
        
        # Check for potential truncation
        if len(text) == 0:
            print("⚠️  WARNING: Empty transcription received")
        
        # Log segments info if available
        if hasattr(transcription, 'segments') and transcription.segments:
            print(f"  Segments: {len(transcription.segments)}")
        
        # Save to history (without filename since we'll delete the audio file)
        history = load_history()
        history_entry = {
            "timestamp": timestamp,
            "filename": None,  # No longer storing audio files
            "text": text,
            "model": model
        }
        history.append(history_entry)
        # Keep history bounded by the configured retention (D5 / BUG-16)
        history, _ = prune_history(history, get_history_retention_days())
        save_history(history)
        dynamo_put_history(g.user_id, history_entry)
        dynamo_log_event(g.user_id, 'transcribe', {'words': len(text.split()), 'chars': len(text), 'model': model})

        # Retain ONLY this user's most recent recording so they can retry without
        # re-recording. Prune is scoped to THIS user's dir (#8) so it can never wipe
        # another user's in-flight audio on a shared server.
        _prune_user_recordings(_user_recordings_dir(g.user_id), filename)
        _last_recording[g.user_id] = {'path': filename, 'model': model}

        # ═══════════════════════════════════════════════════════════════════════════
        # DIAGNOSTIC LOG #9: Final response to client
        # ═══════════════════════════════════════════════════════════════════════════
        print("=" * 80)
        print("📤 FINAL RESPONSE TO CLIENT")
        print("=" * 80)
        print(f"[9] Final text returned to Android: '{text}'")
        print(f"    - final text length: {len(text)} characters")
        print(f"    - timestamp: {timestamp}")
        print("=" * 80)

        return jsonify({
            'success': True,
            'text': text,
            'timestamp': timestamp,
            'filename': None  # audio retained for retry but no playback is exposed
        })

    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/retry', methods=['POST'])
@require_auth
def retry_last():
    """Re-transcribe the most recently captured audio without re-recording.
    Useful when a transcription came back wrong or empty (Tariq #7)."""
    try:
        rec   = _last_recording.get(g.user_id) or {}
        path  = rec.get('path')
        model = rec.get('model') or 'whisper-large-v3'
        if not path or not os.path.exists(path):
            return jsonify({'error': 'No recent audio available to retry'}), 404

        api_key = get_api_key()
        if not api_key:
            return jsonify({'error': 'API key not set. Please configure it in settings.'}), 400
        if not groq_client:
            init_groq_client(api_key)

        with open(path, 'rb') as f:
            file_content = f.read()
        transcription = groq_client.audio.transcriptions.create(
            **build_transcribe_kwargs(path, file_content, model))
        text = transcription.text if hasattr(transcription, 'text') else ""
        text = correct_text(text)

        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S_%f")
        history = load_history()
        history_entry = {"timestamp": timestamp, "filename": None, "text": text, "model": model}
        history.append(history_entry)
        history, _ = prune_history(history, get_history_retention_days())
        save_history(history)
        dynamo_put_history(g.user_id, history_entry)
        dynamo_log_event(g.user_id, 'retry', {'words': len(text.split()), 'model': model})

        return jsonify({'success': True, 'text': text, 'timestamp': timestamp, 'filename': None})
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/event', methods=['POST'])
@require_auth
def log_event():
    """Record a usage/interaction event from the renderer (e.g. app_open).
    No-ops server-side when analytics/cloud is unconfigured."""
    data  = request.json or {}
    event = (data.get('event') or '').strip()
    if not event:
        return jsonify({'error': 'event is required'}), 400
    dynamo_log_event(g.user_id, event, data.get('meta') or {})
    return jsonify({'success': True})

def find_available_port(start_port=8080, max_attempts=100):
    """Find an available port starting from start_port."""
    for port in range(start_port, start_port + max_attempts):
        try:
            # Try to bind to the port - use 127.0.0.1 explicitly for IPv4
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            sock.bind(('127.0.0.1', port))
            sock.close()
            return port
        except OSError:
            continue
    raise RuntimeError(f"Could not find an available port in range {start_port}-{start_port + max_attempts}")

def write_port_file(port):
    """Write the port number to a file for Electron to read (in DATA_DIR)."""
    try:
        with open(PORT_FILE, 'w') as f:
            f.write(str(port))
        print(f"📝 Port {port} written to {PORT_FILE}")
    except Exception as e:
        print(f"⚠️ Could not write port file: {e}")

def cleanup_port_file():
    """Remove the port file on shutdown."""
    try:
        if os.path.exists(PORT_FILE):
            os.remove(PORT_FILE)
    except Exception:
        pass

if __name__ == '__main__':
    # Build self-test: the release script runs the FROZEN exe with ECHO_SELFTEST=1 to
    # prove jose + keyring are actually bundled (guards the jose-less-build regression).
    # Guarded, exits immediately, touches no files/keychain.
    if os.environ.get('ECHO_SELFTEST') == '1':
        import jose, keyring  # noqa: F401 — presence check only
        print('selftest-ok')
        sys.exit(0)

    import atexit

    print("\n" + "="*60)
    print("🎤 Whisper Transcription App")
    print("="*60)
    
    # Move any plaintext secrets into the OS keychain (BUG-17), then run cleanup
    migrate_secrets_to_keyring()
    cleanup_old_recordings()
    cleanup_history()  # prune past-retention history (D5 / BUG-16)
    
    # Register cleanup on exit once (cleanup_port_file is idempotent)
    atexit.register(cleanup_port_file)

    # Find an available port and start serving. find_available_port only PROBES
    # (bind+close), so there's a TOCTOU window before app.run re-binds — another
    # process could grab the port in between. Rather than trust the stale probe, we
    # recover from the real bind failure: if app.run's bind loses the race (OSError),
    # advance to the next port and retry.
    start_port = 8080
    for _ in range(10):
        try:
            port = find_available_port(start_port)
        except RuntimeError as e:
            print(f"❌ {e}")
            sys.exit(1)

        write_port_file(port)
        print(f"\n🚀 Server starting on port {port}")
        print(f"Open your browser and go to: http://127.0.0.1:{port}")
        print("\nPress Ctrl+C to stop the server\n")
        try:
            # Use 127.0.0.1 explicitly to avoid IPv6 issues
            app.run(debug=False, port=port, host='0.0.0.0')
            break  # clean shutdown (or Ctrl+C handled inside app.run)
        except OSError as e:
            # Port was taken in the TOCTOU window before bind — try the next one.
            print(f"⚠️ Port {port} was taken before bind ({e}); retrying on {port + 1}…")
            start_port = port + 1
            continue
        finally:
            cleanup_port_file()
    else:
        print("❌ Could not bind an available port after several attempts.")
        sys.exit(1)