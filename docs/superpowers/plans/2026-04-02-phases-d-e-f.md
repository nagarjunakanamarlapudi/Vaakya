# Phases D + E + F — Backend Simplification, SyncService, Terraform

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Strip the backend to stateless Lambda functions (auth, sync, share, platform AI), build the client SyncService for S3 sync, and deploy via Terraform. Eliminate RDS, App Runner, and all database code.

**Architecture:** Single Lambda (FastAPI + Mangum) behind API Gateway HTTP API. All data lives in S3 (per-user prefixes). Client gets pre-signed URLs and talks to S3 directly. Share links use signed JWTs (no DB lookup). Backend is 100% stateless.

**Tech Stack:** Python 3.12, FastAPI, Mangum, boto3 (S3 pre-signed URLs), python-jose (JWT) | Swift SyncService (URLSession, NWPathMonitor) | Terraform (Lambda, API Gateway, S3, CloudFront, SSM)

**Spec:** `docs/superpowers/specs/2026-04-02-local-first-design.md` Sections 6-9

---

## Execution Strategy

7 tasks. Tasks 1-3 are backend (Phase D). Task 4 is client SyncService (Phase E). Tasks 5-6 are Terraform (Phase F). Task 7 is wiring it all together.

```
Task 1: Strip backend — delete DB code, simplify deps        ─── Phase D
Task 2: Rewrite remaining routers (auth, enhance, share)     ─── Phase D
Task 3: Add sync router + Mangum Lambda adapter              ─── Phase D
Task 4: Client SyncService (S3 sync via pre-signed URLs)     ─── Phase E
Task 5: Terraform — Lambda + API Gateway + S3                ─── Phase F
Task 6: CI/CD — GitHub Actions for Lambda deploy             ─── Phase F
Task 7: Wire client to cloud + integration test              ─── Phase G prep
```

Tasks 1-3 are sequential. Task 4 can run in parallel with 1-3. Tasks 5-6 can run in parallel with 4.

---

## File Structure

### Backend — Delete

```
src/vaakya/
├── db.py                        # DELETE
├── deps.py                      # DELETE (rewrite as simple JWT check)
├── seed.py                      # DELETE
├── models/                      # DELETE entire directory
│   ├── __init__.py
│   ├── base.py
│   ├── meeting.py
│   ├── note.py
│   ├── settings.py
│   ├── share.py
│   └── user.py
├── schemas/                     # DELETE entire directory
│   ├── __init__.py
│   ├── auth.py
│   ├── meeting.py
│   ├── note.py
│   ├── settings.py
│   └── share.py
├── routers/
│   ├── meetings.py              # DELETE
│   ├── notes.py                 # DELETE
│   ├── settings.py              # DELETE
│   └── chat.py                  # DELETE (chat is client-side now via AIService)
alembic/                         # DELETE entire directory
alembic.ini                      # DELETE
docker-compose.yml               # DELETE (no more PostgreSQL)
.env.dev                         # SIMPLIFY (remove DB settings)
.env.test                        # SIMPLIFY
```

### Backend — Keep + Modify

```
src/vaakya/
├── __init__.py
├── main.py                      # REWRITE — remove DB, add Mangum, keep 4 routers
├── config.py                    # SIMPLIFY — remove DB settings, add S3 data bucket
├── routers/
│   ├── __init__.py
│   ├── auth.py                  # REWRITE — stateless (no DB user creation)
│   ├── enhance.py               # REWRITE — transcript in request body (no DB read)
│   └── share.py                 # REWRITE — signed JWT tokens (no DB lookup)
├── services/
│   ├── __init__.py
│   ├── ai.py                    # KEEP (AI prompt + provider routing)
│   └── oauth.py                 # KEEP (Apple/Google token verification)
```

### Backend — New

```
src/vaakya/
├── routers/
│   └── sync.py                  # NEW — pre-signed S3 URL generation
├── deps.py                      # NEW — simple JWT verification (no DB)
├── lambda_handler.py            # NEW — Mangum adapter entry point
Dockerfile.lambda                # NEW — Lambda container image
```

### Client — New

```
VaakyaApp/Sources/
├── Services/
│   └── SyncService.swift        # NEW — S3 sync via pre-signed URLs
```

### Terraform — Modify

```
infra/
├── lambda.tf                    # NEW (replaces apprunner.tf)
├── apigateway.tf                # NEW
├── s3.tf                        # MODIFY — add data bucket for user meetings
├── iam.tf                       # MODIFY — Lambda execution role
├── apprunner.tf                 # DELETE
├── rds.tf                       # DELETE
├── vpc.tf                       # DELETE
```

---

### Task 1: Strip Backend — Delete DB Code

**Files:**
- Delete: `src/vaakya/db.py`, `src/vaakya/seed.py`
- Delete: `src/vaakya/models/` (entire directory)
- Delete: `src/vaakya/schemas/` (entire directory)
- Delete: `src/vaakya/routers/meetings.py`, `notes.py`, `settings.py`, `chat.py`
- Delete: `alembic/` (entire directory), `alembic.ini`
- Delete: `docker-compose.yml`
- Modify: `pyproject.toml` — remove SQLAlchemy, asyncpg, alembic, aiofiles, passlib
- Modify: `.env.dev`, `.env.test` — remove DATABASE_URL and DB settings
- Run: `uv lock` after dependency changes

- [ ] **Step 1: Delete all database-related files**

```bash
cd /Users/nagarjuna/projects/meeting_genie
rm -rf src/vaakya/db.py src/vaakya/seed.py
rm -rf src/vaakya/models/
rm -rf src/vaakya/schemas/
rm -rf src/vaakya/routers/meetings.py src/vaakya/routers/notes.py src/vaakya/routers/settings.py src/vaakya/routers/chat.py
rm -rf alembic/ alembic.ini
rm -f docker-compose.yml
```

- [ ] **Step 2: Simplify pyproject.toml dependencies**

Remove: `aiofiles`, `alembic`, `asyncpg`, `passlib[bcrypt]`, `sqlalchemy[asyncio]`, `uvicorn[standard]`
Add: `mangum>=0.19.0` (Lambda adapter)
Keep: `boto3`, `cryptography`, `fastapi`, `httpx`, `pydantic-settings`, `pydantic[email]`, `python-jose[cryptography]`, `python-multipart`, `slowapi`

```toml
dependencies = [
    "boto3>=1.42.80",
    "cryptography>=44.0.0",
    "fastapi>=0.135.2",
    "httpx>=0.28.1",
    "mangum>=0.19.0",
    "pydantic-settings>=2.13.1",
    "pydantic[email]>=2.12.5",
    "python-jose[cryptography]>=3.5.0",
    "python-multipart>=0.0.22",
    "slowapi>=0.1.9",
]
```

- [ ] **Step 3: Run `uv lock`**

```bash
uv lock
```

- [ ] **Step 4: Simplify .env files**

`.env.dev`:
```
VAAKYA_ENV=dev
JWT_SECRET=dev-secret-change-in-prod
S3_BUCKET=vaakya-data-dev
S3_REGION=us-east-1
S3_ENDPOINT_URL=http://localhost:9010
S3_ACCESS_KEY=minioadmin
S3_SECRET_KEY=minioadmin
AI_PROVIDER=ollama
OLLAMA_BASE_URL=http://localhost:11434
SHARE_SECRET=dev-share-secret-change-in-prod
```

`.env.test`:
```
VAAKYA_ENV=test
JWT_SECRET=test-secret-not-for-production
S3_BUCKET=vaakya-data-test
S3_REGION=us-east-1
SHARE_SECRET=test-share-secret
```

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "chore: strip database code — delete models, schemas, migrations, DB routers"
```

---

### Task 2: Rewrite Remaining Routers

**Files:**
- Rewrite: `src/vaakya/config.py`
- Rewrite: `src/vaakya/deps.py`
- Rewrite: `src/vaakya/routers/auth.py`
- Rewrite: `src/vaakya/routers/enhance.py`
- Rewrite: `src/vaakya/routers/share.py`
- Keep: `src/vaakya/services/ai.py`, `src/vaakya/services/oauth.py`

- [ ] **Step 1: Rewrite config.py — remove DB, add S3 data + share secret**

```python
# src/vaakya/config.py
import os
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    vaakya_env: str = "dev"
    jwt_secret: str
    jwt_algorithm: str = "HS256"
    jwt_expire_minutes: int = 1440
    jwt_refresh_expire_minutes: int = 10080
    # S3 — user data (meetings, audio)
    s3_bucket: str = "vaakya-data-dev"
    s3_region: str = "us-east-1"
    s3_endpoint_url: str = ""  # empty = use real AWS, set for MinIO in dev
    s3_access_key: str = ""
    s3_secret_key: str = ""
    # AI
    ai_provider: str = "ollama"
    ollama_base_url: str = "http://localhost:11434"
    # OAuth
    apple_team_id: str = ""
    apple_key_id: str = ""
    apple_private_key: str = ""
    apple_client_id: str = ""
    google_client_id: str = ""
    # Share links
    share_secret: str = ""

    model_config = {
        "env_file": f".env.{os.getenv('VAAKYA_ENV', 'dev')}",
        "extra": "ignore",
    }

settings = Settings()
```

- [ ] **Step 2: Rewrite deps.py — simple JWT verification, no DB**

```python
# src/vaakya/deps.py
from typing import Annotated
from fastapi import Depends, HTTPException, Header
from jose import jwt, JWTError
from vaakya.config import settings

async def get_current_user_id(authorization: Annotated[str, Header()] = "") -> str:
    """Extract user ID from JWT Bearer token. No DB lookup — stateless."""
    if not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing auth token")
    token = authorization[7:]
    try:
        payload = jwt.decode(token, settings.jwt_secret, algorithms=[settings.jwt_algorithm])
        if payload.get("type") != "access":
            raise HTTPException(status_code=401, detail="Invalid token type")
        user_id = payload.get("sub")
        if not user_id:
            raise HTTPException(status_code=401, detail="Invalid token")
        return user_id
    except JWTError:
        raise HTTPException(status_code=401, detail="Invalid token")

CurrentUserId = Annotated[str, Depends(get_current_user_id)]
```

- [ ] **Step 3: Rewrite auth.py — stateless, no DB user creation**

The auth router keeps the same endpoints but removes all DB operations. In dev mode, it still auto-creates a fake user ID from the token. In prod, it verifies Apple/Google tokens and uses the provider's `sub` as the user ID.

```python
# src/vaakya/routers/auth.py
import logging
from datetime import datetime, timedelta, timezone
from fastapi import APIRouter, HTTPException, Request
from jose import jwt
from pydantic import BaseModel
from slowapi import Limiter
from slowapi.util import get_remote_address
from vaakya.config import settings
from vaakya.services.oauth import OAuthError, verify_apple_identity_token, verify_google_id_token

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/auth", tags=["auth"])
limiter = Limiter(key_func=get_remote_address, enabled=settings.vaakya_env not in ("test",))

class OAuthLoginRequest(BaseModel):
    model_config = {"extra": "forbid"}
    provider: str
    identity_token: str
    name: str | None = None

class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"

class RefreshRequest(BaseModel):
    model_config = {"extra": "forbid"}
    refresh_token: str

def create_tokens(user_id: str) -> tuple[str, str]:
    now = datetime.now(timezone.utc)
    access = jwt.encode(
        {"sub": user_id, "exp": now + timedelta(minutes=settings.jwt_expire_minutes), "type": "access"},
        settings.jwt_secret, algorithm=settings.jwt_algorithm,
    )
    refresh = jwt.encode(
        {"sub": user_id, "exp": now + timedelta(minutes=settings.jwt_refresh_expire_minutes), "type": "refresh"},
        settings.jwt_secret, algorithm=settings.jwt_algorithm,
    )
    return access, refresh

@router.post("/login", response_model=TokenResponse)
@limiter.limit("10/minute")
async def login(request: Request, body: OAuthLoginRequest):
    if settings.vaakya_env in ("dev", "test"):
        user_id = f"dev-{body.identity_token[:16]}"
    elif body.provider == "apple":
        try:
            info = await verify_apple_identity_token(body.identity_token, settings.apple_client_id)
        except OAuthError as exc:
            raise HTTPException(status_code=401, detail=str(exc))
        user_id = f"apple-{info['sub']}"
    elif body.provider == "google":
        try:
            info = await verify_google_id_token(body.identity_token, settings.google_client_id)
        except OAuthError as exc:
            raise HTTPException(status_code=401, detail=str(exc))
        user_id = f"google-{info['sub']}"
    else:
        raise HTTPException(status_code=400, detail=f"Unsupported provider: {body.provider}")

    access, refresh = create_tokens(user_id)
    logger.info("Login: provider=%s user_id=%s", body.provider, user_id)
    return TokenResponse(access_token=access, refresh_token=refresh)

@router.post("/refresh", response_model=TokenResponse)
@limiter.limit("10/minute")
async def refresh(request: Request, body: RefreshRequest):
    try:
        payload = jwt.decode(body.refresh_token, settings.jwt_secret, algorithms=[settings.jwt_algorithm])
        if payload.get("type") != "refresh":
            raise HTTPException(status_code=401, detail="Invalid token type")
        user_id = payload.get("sub")
        if not user_id:
            raise HTTPException(status_code=401, detail="Invalid refresh token")
    except Exception:
        raise HTTPException(status_code=401, detail="Invalid refresh token")
    access, new_refresh = create_tokens(user_id)
    return TokenResponse(access_token=access, refresh_token=new_refresh)
```

- [ ] **Step 4: Rewrite enhance.py — transcript in request body, no DB**

```python
# src/vaakya/routers/enhance.py
import logging
from fastapi import APIRouter, Request
from pydantic import BaseModel
from slowapi import Limiter
from slowapi.util import get_remote_address
from vaakya.config import settings
from vaakya.deps import CurrentUserId
from vaakya.services.ai import enhance_meeting

logger = logging.getLogger(__name__)
router = APIRouter(tags=["enhance"])
limiter = Limiter(key_func=get_remote_address, enabled=settings.vaakya_env not in ("test",))

class EnhanceRequest(BaseModel):
    model_config = {"extra": "forbid"}
    transcript: str
    user_notes: str = ""
    template: str = "general"

class BlockResult(BaseModel):
    type: str
    content: str
    speaker: str | None = None
    meta_text: str | None = None

class EnhanceResponse(BaseModel):
    blocks: list[BlockResult]

@router.post("/enhance", response_model=EnhanceResponse)
@limiter.limit("5/minute")
async def enhance(request: Request, body: EnhanceRequest, user_id: CurrentUserId):
    logger.info("Enhance request: user=%s template=%s transcript_len=%d", user_id, body.template, len(body.transcript))
    blocks = await enhance_meeting(
        transcript=body.transcript,
        user_notes=body.user_notes,
        template=body.template,
        provider=settings.ai_provider,
        api_key=None,
        ollama_model=None,
        ollama_base_url=settings.ollama_base_url,
    )
    return EnhanceResponse(blocks=[
        BlockResult(type=b["type"], content=b["content"], speaker=b.get("speaker"), meta_text=b.get("meta_text"))
        for b in blocks
    ])
```

- [ ] **Step 5: Rewrite share.py — signed JWT tokens, no DB**

```python
# src/vaakya/routers/share.py
import logging
from datetime import datetime, timedelta, timezone
from fastapi import APIRouter, HTTPException, Request
from jose import jwt, JWTError
from pydantic import BaseModel
from vaakya.config import settings
from vaakya.deps import CurrentUserId

logger = logging.getLogger(__name__)
router = APIRouter(tags=["share"])

class ShareRequest(BaseModel):
    model_config = {"extra": "forbid"}
    meeting_id: str
    expires_in_hours: int = 72

class ShareResponse(BaseModel):
    token: str
    url: str
    expires_at: str

@router.post("/share", response_model=ShareResponse)
async def create_share(body: ShareRequest, user_id: CurrentUserId):
    expires_at = datetime.now(timezone.utc) + timedelta(hours=body.expires_in_hours)
    token = jwt.encode(
        {"user_id": user_id, "meeting_id": body.meeting_id, "exp": expires_at},
        settings.share_secret, algorithm="HS256",
    )
    return ShareResponse(token=token, url=f"/share/{token}", expires_at=expires_at.isoformat())

@router.get("/share/{token}")
async def resolve_share(token: str):
    """Verify share token and return pre-signed S3 URL for the meeting.json."""
    try:
        payload = jwt.decode(token, settings.share_secret, algorithms=["HS256"])
    except JWTError:
        raise HTTPException(status_code=404, detail="Invalid or expired share link")

    user_id = payload["user_id"]
    meeting_id = payload["meeting_id"]

    import boto3
    s3_kwargs = {"region_name": settings.s3_region}
    if settings.s3_endpoint_url:
        s3_kwargs["endpoint_url"] = settings.s3_endpoint_url
        s3_kwargs["aws_access_key_id"] = settings.s3_access_key
        s3_kwargs["aws_secret_access_key"] = settings.s3_secret_key
    s3 = boto3.client("s3", **s3_kwargs)

    key = f"users/{user_id}/meetings/{meeting_id}/meeting.json"
    try:
        url = s3.generate_presigned_url(
            "get_object",
            Params={"Bucket": settings.s3_bucket, "Key": key},
            ExpiresIn=300,
        )
    except Exception:
        raise HTTPException(status_code=404, detail="Meeting not found")

    return {"meeting_url": url, "user_id": user_id, "meeting_id": meeting_id}
```

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: rewrite routers — stateless auth, enhance with transcript body, signed share tokens"
```

---

### Task 3: Sync Router + Mangum Lambda Adapter

**Files:**
- Create: `src/vaakya/routers/sync.py`
- Create: `src/vaakya/lambda_handler.py`
- Rewrite: `src/vaakya/main.py`
- Create: `Dockerfile.lambda`

- [ ] **Step 1: Create sync.py — pre-signed S3 URL generation**

```python
# src/vaakya/routers/sync.py
import logging
import boto3
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from vaakya.config import settings
from vaakya.deps import CurrentUserId

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/sync", tags=["sync"])

class PresignRequest(BaseModel):
    model_config = {"extra": "forbid"}
    action: str  # "put" or "get"
    key: str     # e.g. "meetings/{id}/meeting.json" or "meetings/{id}/audio.m4a"

class PresignResponse(BaseModel):
    url: str
    expires_in: int = 300

def _get_s3_client():
    kwargs = {"region_name": settings.s3_region}
    if settings.s3_endpoint_url:
        kwargs["endpoint_url"] = settings.s3_endpoint_url
        kwargs["aws_access_key_id"] = settings.s3_access_key
        kwargs["aws_secret_access_key"] = settings.s3_secret_key
    return boto3.client("s3", **kwargs)

@router.post("/presign", response_model=PresignResponse)
async def presign(body: PresignRequest, user_id: CurrentUserId):
    """Generate a pre-signed S3 URL scoped to the user's prefix."""
    # Validate action
    if body.action not in ("put", "get"):
        raise HTTPException(status_code=400, detail="action must be 'put' or 'get'")

    # Scope the key to the user's S3 prefix (security: prevent accessing other users' data)
    scoped_key = f"users/{user_id}/{body.key}"

    s3 = _get_s3_client()
    client_method = "put_object" if body.action == "put" else "get_object"

    try:
        url = s3.generate_presigned_url(
            client_method,
            Params={"Bucket": settings.s3_bucket, "Key": scoped_key},
            ExpiresIn=300,
        )
    except Exception as e:
        logger.error("Failed to generate pre-signed URL: %s", e)
        raise HTTPException(status_code=500, detail="Failed to generate URL")

    logger.info("Presign: user=%s action=%s key=%s", user_id, body.action, scoped_key)
    return PresignResponse(url=url)

@router.get("/index")
async def get_index_url(user_id: CurrentUserId):
    """Get a pre-signed URL to download the user's index.json."""
    scoped_key = f"users/{user_id}/index.json"
    s3 = _get_s3_client()
    try:
        url = s3.generate_presigned_url(
            "get_object",
            Params={"Bucket": settings.s3_bucket, "Key": scoped_key},
            ExpiresIn=300,
        )
    except Exception:
        raise HTTPException(status_code=404, detail="Index not found")
    return {"url": url}
```

- [ ] **Step 2: Rewrite main.py — remove DB, add sync router, keep it minimal**

```python
# src/vaakya/main.py
import logging
from fastapi import FastAPI, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded
from slowapi.util import get_remote_address
from vaakya.config import settings
from vaakya.routers import auth, enhance, share, sync

logger = logging.getLogger(__name__)

limiter = Limiter(
    key_func=get_remote_address,
    enabled=settings.vaakya_env not in ("test",),
)

app = FastAPI(title="Vaakya API", version="0.2.0")
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

# CORS
_cors_origins = (
    ["http://localhost:*", "http://127.0.0.1:*"]
    if settings.vaakya_env in ("dev", "test")
    else ["https://vaakya.app", "https://*.cloudfront.net"]
)
app.add_middleware(
    CORSMiddleware,
    allow_origins=_cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.middleware("http")
async def security_headers(request: Request, call_next):
    response: Response = await call_next(request)
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    if settings.vaakya_env not in ("dev", "test"):
        response.headers["Strict-Transport-Security"] = "max-age=63072000; includeSubDomains"
    return response

# Routers — only 4 (auth, enhance, share, sync)
app.include_router(auth.router)
app.include_router(enhance.router)
app.include_router(share.router)
app.include_router(sync.router)

@app.get("/health")
async def health():
    return {"status": "ok", "env": settings.vaakya_env, "version": "0.2.0"}
```

- [ ] **Step 3: Create lambda_handler.py — Mangum adapter**

```python
# src/vaakya/lambda_handler.py
from mangum import Mangum
from vaakya.main import app

handler = Mangum(app, lifespan="off")
```

- [ ] **Step 4: Create Dockerfile.lambda**

```dockerfile
# Dockerfile.lambda
FROM python:3.12-slim
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv
WORKDIR /app
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev
COPY src/ src/
ENV PATH="/app/.venv/bin:$PATH"
CMD ["vaakya.lambda_handler.handler"]
```

- [ ] **Step 5: Update Makefile — add Lambda dev server**

Add to root Makefile:
```makefile
dev:                         ## Run API locally (for testing sync/share)
	VAAKYA_ENV=dev uv run uvicorn vaakya.main:app --reload --port 8002
```

Note: `uvicorn` is no longer a dependency (removed in Task 1). Add it back to dev dependencies only:
```toml
[dependency-groups]
dev = [
    "httpx>=0.28.1",
    "pytest>=9.0.2",
    "pytest-asyncio>=1.3.0",
    "ruff>=0.11.0",
    "uvicorn[standard]>=0.42.0",
]
```

- [ ] **Step 6: Write tests**

Delete all old DB-dependent tests. Write new stateless tests:

`tests/test_auth.py` — test login (dev mode), refresh, invalid tokens
`tests/test_enhance.py` — test enhance with mocked AI (transcript in body)
`tests/test_share.py` — test create share token, resolve share token, expired token
`tests/test_sync.py` — test presign URL generation, index URL, auth required
`tests/test_health.py` — test health endpoint

All tests use `httpx.AsyncClient` with `ASGITransport(app=app)` — no database needed.

- [ ] **Step 7: Run tests**

```bash
VAAKYA_ENV=test uv run pytest tests/ -v
```

- [ ] **Step 8: Commit**

```bash
git add -A && git commit -m "feat: sync router, Mangum Lambda adapter, stateless tests"
```

---

### Task 4: Client SyncService

**Files:**
- Create: `VaakyaApp/Sources/Services/SyncService.swift`
- Modify: `VaakyaApp/Sources/Views/SettingsView.swift` (add sync UI)
- Modify: `VaakyaApp/Sources/ViewModels/AuthViewModel.swift` (trigger sync on sign-in)

- [ ] **Step 1: Create SyncService.swift**

```swift
// VaakyaApp/Sources/Services/SyncService.swift
import Foundation
import Network

@MainActor
@Observable
final class SyncService {
    static let shared = SyncService()

    var isSyncing = false
    var lastSyncDate: Date?
    var syncError: String?
    var isWifi = true

    private let monitor = NWPathMonitor()

    private init() {
        // Monitor network type for audio sync policy
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isWifi = path.usesInterfaceType(.wifi)
            }
        }
        monitor.start(queue: DispatchQueue(label: "vaakya.network"))
    }

    // MARK: - Full Sync

    /// Pull server index, diff with local, push/pull changed meetings.
    func sync() async {
        guard !isSyncing else { return }
        guard KeychainService.load(key: "access_token") != nil else { return }

        isSyncing = true
        syncError = nil
        defer { isSyncing = false }

        do {
            // 1. Get server index
            let serverIndex = try await fetchServerIndex()

            // 2. Diff with local
            let localMeetings = LocalStore.shared.meetings
            let localById = Dictionary(uniqueKeysWithValues: localMeetings.map { ($0.id, $0) })
            let serverById = Dictionary(uniqueKeysWithValues: serverIndex.map { ($0.id, $0) })

            // 3. Push local-newer meetings
            for local in localMeetings {
                if let server = serverById[local.id] {
                    if local.lastModified > server.lastModified {
                        try await pushMeeting(id: local.id)
                    }
                } else {
                    // New locally, not on server
                    try await pushMeeting(id: local.id)
                }
            }

            // 4. Pull server-newer meetings
            for server in serverIndex {
                if let local = localById[server.id] {
                    if server.lastModified > local.lastModified {
                        try await pullMeeting(id: server.id)
                    }
                } else {
                    // New on server, not local
                    try await pullMeeting(id: server.id)
                }
            }

            // 5. Push updated index
            try await pushIndex()

            lastSyncDate = Date()
            print("[SyncService] Sync complete")
        } catch {
            syncError = error.localizedDescription
            print("[SyncService] Sync failed: \(error)")
        }
    }

    /// Push all meetings (first sync after sign-in).
    func pushAll() async {
        for meeting in LocalStore.shared.meetings {
            try? await pushMeeting(id: meeting.id)
        }
        try? await pushIndex()
    }

    // MARK: - Individual Operations

    func pushMeeting(id: String) async throws {
        guard let doc = LocalStore.shared.loadMeeting(id: id) else { return }
        let data = try JSONEncoder.vaakya.encode(doc)

        // Get pre-signed PUT URL for meeting.json
        let url = try await getPresignedURL(action: "put", key: "meetings/\(id)/meeting.json")
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.httpBody = data
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw SyncError.pushFailed(id)
        }

        // Push audio if on Wi-Fi
        if isWifi, let audioURL = LocalStore.shared.audioURL(for: id) {
            let audioData = try Data(contentsOf: audioURL)
            let audioPresignURL = try await getPresignedURL(action: "put", key: "meetings/\(id)/audio.m4a")
            var audioReq = URLRequest(url: audioPresignURL)
            audioReq.httpMethod = "PUT"
            audioReq.httpBody = audioData
            audioReq.setValue("audio/mp4", forHTTPHeaderField: "Content-Type")
            let (_, audioResp) = try await URLSession.shared.data(for: audioReq)
            guard let audioHttp = audioResp as? HTTPURLResponse, (200...299).contains(audioHttp.statusCode) else {
                print("[SyncService] Audio push failed for \(id) (non-critical)")
                return // Audio push failure is non-critical
            }
        }

        print("[SyncService] Pushed meeting \(id)")
    }

    func pullMeeting(id: String) async throws {
        let url = try await getPresignedURL(action: "get", key: "meetings/\(id)/meeting.json")
        let (data, _) = try await URLSession.shared.data(from: url)
        let doc = try JSONDecoder.vaakya.decode(MeetingDocument.self, from: data)
        LocalStore.shared.createMeeting(doc) // createMeeting handles update-if-exists via WAL
        print("[SyncService] Pulled meeting \(id)")
    }

    // MARK: - Helpers

    private func getPresignedURL(action: String, key: String) async throws -> URL {
        guard let token = KeychainService.load(key: "access_token") else {
            throw SyncError.notSignedIn
        }

        #if DEBUG
        let baseURL = "http://localhost:8002"
        #else
        let baseURL = "https://api.vaakya.app"
        #endif

        var request = URLRequest(url: URL(string: "\(baseURL)/sync/presign")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(["action": action, "key": key])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw SyncError.presignFailed
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let urlString = json["url"] as? String,
              let url = URL(string: urlString) else {
            throw SyncError.invalidPresignResponse
        }
        return url
    }

    private func fetchServerIndex() async throws -> [MeetingMetadata] {
        let url = try await getPresignedURL(action: "get", key: "index.json")
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            return [] // No index yet = first sync
        }
        return (try? JSONDecoder.vaakya.decode([MeetingMetadata].self, from: data)) ?? []
    }

    private func pushIndex() async throws {
        let data = try JSONEncoder.vaakya.encode(LocalStore.shared.meetings)
        let url = try await getPresignedURL(action: "put", key: "index.json")
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.httpBody = data
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (_, _) = try await URLSession.shared.data(for: request)
    }

    enum SyncError: Error, LocalizedError {
        case notSignedIn
        case presignFailed
        case invalidPresignResponse
        case pushFailed(String)
        case pullFailed(String)

        var errorDescription: String? {
            switch self {
            case .notSignedIn: return "Sign in to sync"
            case .presignFailed: return "Failed to get sync URL"
            case .invalidPresignResponse: return "Invalid sync response"
            case .pushFailed(let id): return "Failed to push meeting \(id)"
            case .pullFailed(let id): return "Failed to pull meeting \(id)"
            }
        }
    }
}

// JSON encoder/decoder with ISO8601 dates (matching LocalStore)
extension JSONEncoder {
    static let vaakya: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}

extension JSONDecoder {
    static let vaakya: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
```

- [ ] **Step 2: Add sync UI to SettingsView Account tab**

In the Account tab of SettingsView, add:
- "Sign in to sync across devices" button (if not signed in)
- "Sync Now" button (if signed in)
- Last sync date
- Sync status indicator

- [ ] **Step 3: Trigger sync on sign-in**

In AuthViewModel, after successful login, call `SyncService.shared.pushAll()` to push all local meetings to S3.

- [ ] **Step 4: Auto-sync after meeting save**

In MeetingViewModel, after `updateMeeting` or `stopStreamingTranscription`, if user is signed in, push the meeting:
```swift
if KeychainService.load(key: "access_token") != nil {
    Task { try? await SyncService.shared.pushMeeting(id: meetingId) }
}
```

- [ ] **Step 5: Build and verify**

```bash
cd /Users/nagarjuna/projects/meeting_genie/VaakyaApp && swift build
```

- [ ] **Step 6: Commit**

```bash
git commit -m "feat: SyncService — S3 sync via pre-signed URLs, Wi-Fi audio policy"
```

---

### Task 5: Terraform — Lambda + API Gateway + S3

**Files:**
- Delete: `infra/apprunner.tf`, `infra/rds.tf`, `infra/vpc.tf`
- Create: `infra/lambda.tf`, `infra/apigateway.tf`
- Modify: `infra/s3.tf`, `infra/iam.tf`, `infra/main.tf`, `infra/variables.tf`, `infra/outputs.tf`

- [ ] **Step 1: Delete App Runner + RDS + VPC Terraform**

```bash
rm infra/apprunner.tf infra/rds.tf infra/vpc.tf
```

- [ ] **Step 2: Create lambda.tf**

Lambda function using container image from ECR:
- Memory: 256MB (dev), 512MB (prod)
- Timeout: 30s (auth/sync/share), 120s (enhance)
- Environment variables from SSM
- Execution role with S3 + SSM read access

- [ ] **Step 3: Create apigateway.tf**

API Gateway HTTP API:
- Routes mapped to Lambda
- CORS configuration
- Default stage with auto-deploy

- [ ] **Step 4: Update s3.tf — add data bucket**

Add `vaakya-data-{stage}` bucket for user meetings/audio. Private, no public access.

- [ ] **Step 5: Update iam.tf — Lambda execution role**

Lambda role needs: S3 read/write on data bucket, SSM read on `/vaakya/{stage}/*`, CloudWatch logs.

- [ ] **Step 6: Update outputs.tf**

Output: API Gateway URL, S3 data bucket name, Lambda function ARN.

- [ ] **Step 7: Validate**

```bash
cd infra && terraform init -backend=false && terraform validate && terraform fmt -check
```

- [ ] **Step 8: Commit**

```bash
git commit -m "feat: Terraform — Lambda + API Gateway + S3 (replace App Runner + RDS)"
```

---

### Task 6: CI/CD — GitHub Actions for Lambda Deploy

**Files:**
- Modify: `.github/workflows/deploy.yml`

- [ ] **Step 1: Update deploy workflow**

Build Docker image, push to ECR, update Lambda function code. Replace App Runner deploy step.

```yaml
- name: Update Lambda
  run: |
    aws lambda update-function-code \
      --function-name vaakya-api-${{ env.STAGE }} \
      --image-uri ${{ env.IMAGE }}
```

- [ ] **Step 2: Commit**

```bash
git commit -m "ci: deploy to Lambda instead of App Runner"
```

---

### Task 7: Wire Client to Cloud + Smoke Test

**Files:**
- Modify: `VaakyaApp/Sources/API/APIClient.swift` — update base URL for API Gateway
- Modify: `VaakyaApp/Sources/Services/AIService.swift` — Platform AI calls new endpoint

- [ ] **Step 1: Update APIClient base URL**

Production URL changes from App Runner to API Gateway default URL. Update the `#else` branch.

- [ ] **Step 2: Smoke test checklist**

```
Local (no server):
- [ ] App launches, record, transcribe, enhance with Ollama — all works offline

With dev server running (make dev):
- [ ] Sign in with Google (dev mode)
- [ ] Sync: meetings pushed to MinIO/S3
- [ ] Share: create link, resolve link
- [ ] Platform AI: enhance via server
- [ ] Sign out
- [ ] App continues working offline
```

- [ ] **Step 3: Commit**

```bash
git commit -m "feat: wire client to cloud endpoints, smoke test passes"
```
