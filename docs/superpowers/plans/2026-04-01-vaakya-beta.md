# Vaakya Public Beta — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Take Vaakya from working prototype to public beta (TestFlight, 50-100 users) with on-device transcription, speaker diarization, calendar integration, iOS app, and a revised Apple-native design system.

**Architecture:** Local-first macOS + iOS app (SwiftUI, mlx-swift, ONNX Runtime) with a thin FastAPI backend on AWS (App Runner, RDS PostgreSQL, S3) for auth, cloud AI, sync, and sharing. All transcription and speaker ID happens on-device. Server is optional.

**Tech Stack:** Swift 5.9+, SwiftUI, mlx-swift (Whisper), onnxruntime-swift (pyannote), EventKit, AVFoundation, CoreAudio | Python 3.12, FastAPI, SQLAlchemy 2.0 async, PostgreSQL, S3, App Runner | GitHub Actions, Docker, ECR

**Spec:** `docs/superpowers/specs/2026-04-01-vaakya-beta-design.md`

---

## Execution Strategy

4 phases. Tasks within the same phase can run in parallel on separate worktrees.

```
Phase 1: Foundation (sequential — unblocks everything)
  Task 1: Deployment infrastructure
  Task 2: Real OAuth (Apple + Google)

Phase 2: Core Features (4 parallel agents)
  Task 3: Design system overhaul ──────── Agent A (worktree)
  Task 4: MLX Whisper on-device ────────── Agent B (worktree)
  Task 5: pyannote speaker diarization ── Agent C (worktree)
  Task 6: Calendar / EventKit ──────────── Agent D (worktree)

Phase 3: Integration (2 parallel agents, after Phase 2 merge)
  Task 7: iOS platform adaptation ──────── Agent E (worktree)
  Task 8: Dashboard + UX patterns ──────── Agent F (worktree)

Phase 4: Polish (4 parallel agents)
  Task 9:  Web share viewer ────────────── Agent G (worktree)
  Task 10: Onboarding flow ────────────── Agent H (worktree)
  Task 11: Floating pill hardening ─────── Agent I (worktree)
  Task 12: Error/empty/loading states ──── Agent J (worktree)

Phase 5: Final (sequential)
  Task 13: TestFlight readiness + E2E
```

**Merge strategy:** Each worktree agent works on a feature branch. After completing a task, create a PR to main. Tasks in the same phase have no file conflicts by design — they touch different files. Merge PRs before starting next phase.

---

## Cross-Cutting: Testing, Security, Dev Environment

These requirements apply to EVERY task. Agents must follow these standards.

### Testing Strategy

**Three layers — all required for every feature:**

| Layer | Backend (Python) | Client (Swift) |
|---|---|---|
| **Unit** | pytest, each service/router has `tests/test_*.py`. Mock external deps (AI APIs, S3). Run: `uv run pytest tests/unit/ -v` | XCTest, each Service/ViewModel has corresponding test. Mock network, storage. Run: `swift test` |
| **Integration** | pytest with real test PostgreSQL (Docker). Test full request → DB → response. Run: `uv run pytest tests/integration/ -v` | Test against running local backend. Verify full data flow (record → transcribe → enhance → display). |
| **E2E** | httpx TestClient against full app with test DB. Covers auth → CRUD → enhance → share. Run: `uv run pytest tests/e2e/ -v` | `E2ETest.swift` against live backend. Full user journey: login → record → transcribe → enhance → share. Run: `make e2e` |

**Test file structure (backend):**
```
tests/
├── conftest.py            # Shared fixtures: test DB, client, auth headers
├── unit/
│   ├── test_oauth.py      # OAuth token verification (mocked providers)
│   ├── test_ai_service.py # AI routing (mocked APIs)
│   ├── test_models.py     # SQLAlchemy model validation
│   └── test_schemas.py    # Pydantic schema validation
├── integration/
│   ├── test_auth.py       # Full auth flow with real DB
│   ├── test_meetings.py   # Meeting CRUD with real DB
│   ├── test_notes.py      # Block CRUD with real DB
│   ├── test_enhance.py    # Enhancement with mocked AI, real DB
│   ├── test_share.py      # Share links with real DB
│   └── test_settings.py   # Settings with real DB
└── e2e/
    ├── test_full_flow.py  # Login → create meeting → add blocks → enhance → share → verify
    └── test_share_public.py # Public share link access without auth
```

**Test file structure (Swift):**
```
VaakyaApp/Tests/
├── Unit/
│   ├── TranscriptionServiceTests.swift
│   ├── DiarizationServiceTests.swift
│   ├── CalendarServiceTests.swift
│   ├── KeychainServiceTests.swift
│   ├── MeetingSourceDetectorTests.swift
│   ├── ModelManagerTests.swift
│   └── AudioDeviceManagerTests.swift
├── Integration/
│   ├── APIClientTests.swift    # Against local backend
│   └── AuthFlowTests.swift     # Full auth cycle
└── E2ETest.swift               # Full user journey
```

**Test requirements per task:**
- Every new service/router MUST have unit tests before implementation (TDD where practical)
- Integration tests run against real PostgreSQL via Docker (conftest.py creates/drops test DB)
- E2E tests run as part of CI before deploy
- Minimum coverage: 80% on backend, best-effort on Swift (no hard gate, but all public APIs tested)

**CI test pipeline (add to `.github/workflows/deploy.yml`):**
```yaml
jobs:
  test:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:16
        env:
          POSTGRES_DB: vaakya_test
          POSTGRES_USER: vaakya
          POSTGRES_PASSWORD: vaakya
        ports: ['5432:5432']
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
    steps:
      - uses: actions/checkout@v4
      - uses: astral-sh/setup-uv@v5
      - run: uv sync --frozen
      - run: uv run pytest tests/ -v --tb=short
        env:
          DATABASE_URL: postgresql+asyncpg://vaakya:vaakya@localhost:5432/vaakya_test
          JWT_SECRET: test-secret-key-not-for-production
          VAAKYA_ENV: test

  deploy:
    needs: test
    # ... existing deploy job
```

### Security

**Backend security (enforced in every task that touches backend):**

| Concern | Implementation |
|---|---|
| Input validation | Pydantic schemas on all request bodies. Reject unexpected fields (`model_config = {"extra": "forbid"}`). |
| Auth | JWT with short-lived access tokens (24h), refresh tokens (7d). Verify on every protected endpoint via `CurrentUser` dependency. |
| Rate limiting | `slowapi` middleware: 100 req/min per user on general endpoints, 10 req/min on `/auth/login`, 5 req/min on `/enhance` and `/chat` (these call expensive APIs). |
| CORS | Dev: allow `localhost:*`. Prod: allow only `https://vaakya.app`, `https://share.vaakya.app`. No wildcard. |
| Secrets | Never in code or git. All via env vars / AWS Secrets Manager. `.env.stg` and `.env.prod` in `.gitignore`. |
| SQL injection | SQLAlchemy ORM only — no raw SQL strings. Parameterized queries always. |
| S3 | Private bucket. Pre-signed URLs for client uploads (expire in 15 min). No public read. |
| HTTPS | ACM certificate on App Runner. Force HTTPS redirect. HSTS header. |
| Dependencies | `uv audit` in CI to catch known vulnerabilities. Dependabot alerts enabled. |
| API keys (BYOK) | User API keys stored encrypted at rest in PostgreSQL (Fernet symmetric encryption, key from Secrets Manager). Never logged. Never returned in full via API (mask as `sk-...xxxx`). |
| Headers | `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`, `Strict-Transport-Security`. FastAPI middleware. |

**Client security:**
| Concern | Implementation |
|---|---|
| Token storage | Keychain only (not UserDefaults, not files). `kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. |
| Network | All API calls over HTTPS. Certificate pinning for `api.vaakya.app` (optional for beta, recommended for prod). |
| Audio files | Stored in app sandbox (`~/Library/Application Support/Vaakya/`). Not in shared directories. Not in iCloud Drive (exclude via `.nosync` or resource values). |
| API keys (BYOK) | Stored in Keychain alongside auth tokens. Never sent to Vaakya backend — client calls AI providers directly. |

**Add to pyproject.toml dependencies:**
```
"slowapi>=0.1.9",
"cryptography>=44.0.0",
```

### Developer Environment

**Backend dev setup (Makefile commands):**

```makefile
# Makefile
.PHONY: up down dev test test-unit test-integration test-e2e migrate seed lint

up:                          ## Start PostgreSQL + MinIO via Docker Compose
	docker compose up -d

down:                        ## Stop containers
	docker compose down

dev:                         ## Run FastAPI with hot reload
	VAAKYA_ENV=dev uv run uvicorn vaakya.main:app --reload --port 8000

test:                        ## Run all tests
	VAAKYA_ENV=test uv run pytest tests/ -v --tb=short

test-unit:                   ## Run unit tests only
	VAAKYA_ENV=test uv run pytest tests/unit/ -v

test-integration:            ## Run integration tests (requires Docker)
	VAAKYA_ENV=test uv run pytest tests/integration/ -v

test-e2e:                    ## Run E2E tests
	VAAKYA_ENV=test uv run pytest tests/e2e/ -v

migrate:                     ## Run Alembic migrations
	uv run alembic upgrade head

seed:                        ## Seed dev data
	uv run python -m vaakya.seed

lint:                        ## Lint + format
	uv run ruff check src/ tests/ --fix
	uv run ruff format src/ tests/

audit:                       ## Check for dependency vulnerabilities
	uv audit
```

**Swift dev setup (VaakyaApp/Makefile):**

```makefile
.PHONY: build run test e2e clean

build:                       ## Build macOS app
	swift build

run:                         ## Build and run
	swift build && open .build/debug/Vaakya.app

test:                        ## Run unit + integration tests
	swift test

e2e:                         ## Run E2E tests against local backend
	swift build && .build/debug/Vaakya --e2e

clean:                       ## Clean build artifacts
	swift package clean
```

**Docker Compose (verify current, update if needed):**
- PostgreSQL 16 on port 5432
- MinIO on ports 9002 (API) / 9003 (console)
- No Redis (removed for beta)
- Health checks on all services

**Environment files:**
- `.env.dev` — checked into git (safe defaults, localhost everything)
- `.env.test` — checked into git (test DB, test secrets)
- `.env.stg` — gitignored (AWS staging credentials)
- `.env.prod` — gitignored (AWS prod credentials)

Create `.env.test`:
```
VAAKYA_ENV=test
DATABASE_URL=postgresql+asyncpg://vaakya:vaakya@localhost:5432/vaakya_test
JWT_SECRET=test-secret-not-for-production
S3_ENDPOINT_URL=http://localhost:9000
S3_ACCESS_KEY=minioadmin
S3_SECRET_KEY=minioadmin
S3_BUCKET=vaakya-test
APPLE_CLIENT_ID=com.vaakya.test
GOOGLE_CLIENT_ID=test-google-client-id
```

### Production Quality Standards

Every agent must follow these:

1. **Error handling:** Catch and handle errors at service boundaries. Never swallow exceptions silently. Log errors with context (user ID, meeting ID, operation). Return meaningful error responses (not 500 with stack trace).

2. **Logging:** Use Python `logging` module (not print). Structured JSON logs in production. Log: auth events, API errors, AI provider calls, model downloads.

3. **Health check:** `GET /health` returns DB connectivity status, current version, environment name.

4. **Graceful shutdown:** FastAPI lifespan handler closes DB connections, cancels background tasks.

5. **Database:** Connection pooling via SQLAlchemy async engine (pool_size=5, max_overflow=10 for beta). Alembic migration for every schema change — no manual DDL.

6. **Idempotency:** POST endpoints that create resources use idempotency keys or check-before-create to prevent duplicates (already done for share links, apply to other endpoints).

7. **Pagination:** List endpoints (`GET /meetings`) use cursor-based pagination (default 20, max 100).

---

## File Structure (New + Modified)

### New Swift Files

```
VaakyaApp/Sources/
├── Theme/
│   ├── DesignTokens.swift          # Color palette, spacing, radius, typography
│   └── ThemeManager.swift          # Light/dark mode, user preference
├── Services/
│   ├── TranscriptionService.swift  # Protocol + MLX Whisper integration
│   ├── DiarizationService.swift    # pyannote ONNX speaker diarization
│   ├── ModelManager.swift          # Download/manage Whisper + pyannote models
│   ├── CalendarService.swift       # EventKit integration
│   ├── KeychainService.swift       # Secure token storage
│   ├── AudioDeviceManager.swift    # Device detection + switching (macOS)
│   ├── AudioDeviceManagerIOS.swift # Device detection (iOS)
│   └── MeetingSourceDetector.swift # Detect Zoom/Meet/Teams from calendar or process
├── Views/
│   ├── DashboardView.swift         # Home screen with stats, quick start, recent
│   ├── OnboardingView.swift        # First-launch flow
│   ├── SpeakerMatchingView.swift   # Match diarized speakers to calendar participants
│   ├── ContextualSidebar.swift     # Share + Ask Vaakya sidebar
│   └── PrivacyBadge.swift          # "Processed on your Mac" badge component
├── ViewModels/
│   └── CalendarViewModel.swift     # Calendar events, next meeting, auto-start
└── iOS/
    ├── iOSMainView.swift           # NavigationStack layout for iPhone
    ├── iOSRecordingView.swift      # Background recording + lock screen controls
    └── NextMeetingCard.swift       # "Next Meeting" card for iOS home
```

### New Backend Files

```
src/vaakya/
├── routers/
│   └── auth.py                     # MODIFY: Add Apple/Google OAuth verification
├── services/
│   └── oauth.py                    # NEW: Apple/Google token verification
Dockerfile                          # NEW
.github/workflows/deploy.yml        # NEW
share-viewer/                       # NEW: Static SPA
├── index.html
├── styles.css
└── app.js
```

### Modified Files

```
VaakyaApp/
├── Package.swift                   # Add mlx-swift, onnxruntime-swift dependencies
├── Sources/
│   ├── VaakyaApp.swift             # Theme, menu bar overhaul, platform conditionals
│   ├── API/APIClient.swift         # Base URL config, Keychain tokens
│   ├── API/Models.swift            # Add speaker, participants, source fields
│   ├── Services/AudioRecorder.swift # Device management integration
│   ├── Views/MainView.swift        # Design system + dashboard
│   ├── Views/SidebarView.swift     # Design system + source tags
│   ├── Views/MeetingDetailView.swift # Design system + contextual sidebar + privacy badge
│   ├── Views/BlockView.swift       # Design system colors
│   ├── Views/TranscriptView.swift  # Real speaker labels + filter
│   ├── Views/LoginView.swift       # Apple + Google sign in
│   ├── Views/SettingsView.swift    # Tabbed layout, model management
│   ├── Views/FloatingNotepad.swift # Hardening
│   ├── Views/RecordingPillView.swift # Hardening
│   ├── ViewModels/AuthViewModel.swift # Real OAuth + Keychain
│   └── ViewModels/MeetingViewModel.swift # Local transcription, diarization, calendar
src/vaakya/
├── config.py                       # Add Apple/Google OAuth settings
├── models/meeting.py               # Add source, participants fields
├── schemas/meeting.py              # Add source, participants
├── schemas/auth.py                 # Add OAuth token fields
└── routers/auth.py                 # Real OAuth verification
```

---

## Phase 1: Foundation

### Task 1: Deployment Infrastructure

**Files:**
- Create: `Dockerfile`
- Create: `.github/workflows/deploy.yml`
- Modify: `src/vaakya/config.py`
- Modify: `pyproject.toml`

- [ ] **Step 1: Create Dockerfile**

```dockerfile
# Dockerfile
FROM python:3.12-slim AS builder
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv
WORKDIR /app
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev
COPY src/ src/
COPY alembic/ alembic/
COPY alembic.ini .

FROM python:3.12-slim
WORKDIR /app
COPY --from=builder /app /app
ENV PATH="/app/.venv/bin:$PATH"
EXPOSE 8000
CMD ["sh", "-c", "alembic upgrade head && uvicorn vaakya.main:app --host 0.0.0.0 --port 8000"]
```

- [ ] **Step 2: Test Docker build locally**

```bash
docker build -t vaakya-api .
docker run --rm -p 8000:8000 --env-file .env.dev --network host vaakya-api
```

Expected: Container starts, health endpoint responds at localhost:8000/health.

- [ ] **Step 3: Create GitHub Actions deploy workflow**

```yaml
# .github/workflows/deploy.yml
name: Deploy API
on:
  push:
    branches: [main]
    paths: ['src/**', 'Dockerfile', 'alembic/**', 'pyproject.toml']

env:
  AWS_REGION: us-east-1
  ECR_REPOSITORY: vaakya-api

jobs:
  deploy:
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read
    steps:
      - uses: actions/checkout@v4

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-arn: ${{ secrets.AWS_ROLE_ARN }}
          aws-region: ${{ env.AWS_REGION }}

      - name: Login to ECR
        id: ecr
        uses: aws-actions/amazon-ecr-login@v2

      - name: Build + push image
        run: |
          IMAGE=${{ steps.ecr.outputs.registry }}/${{ env.ECR_REPOSITORY }}:${{ github.sha }}
          docker build -t $IMAGE .
          docker push $IMAGE
          echo "IMAGE=$IMAGE" >> $GITHUB_ENV

      - name: Deploy to App Runner
        run: |
          aws apprunner update-service \
            --service-arn ${{ secrets.APPRUNNER_SERVICE_ARN }} \
            --source-configuration '{"ImageRepository":{"ImageIdentifier":"'"$IMAGE"'","ImageRepositoryType":"ECR","ImageConfiguration":{"Port":"8000"}}}'
```

- [ ] **Step 4: Update config.py for environment-aware settings**

Modify `src/vaakya/config.py` — add env file selection:

```python
from pydantic_settings import BaseSettings
import os

class Settings(BaseSettings):
    vaakya_env: str = "dev"
    database_url: str
    s3_endpoint_url: str = "http://localhost:9000"
    s3_access_key: str = "minioadmin"
    s3_secret_key: str = "minioadmin"
    s3_bucket: str = "vaakya-dev"
    s3_region: str = "us-east-1"
    jwt_secret: str
    jwt_algorithm: str = "HS256"
    jwt_expire_minutes: int = 1440
    jwt_refresh_expire_minutes: int = 10080  # 7 days
    ai_provider: str = "ollama"
    ollama_base_url: str = "http://localhost:11434"
    base_url: str = "http://localhost:8001"
    # OAuth
    apple_team_id: str = ""
    apple_key_id: str = ""
    apple_private_key: str = ""  # PEM content or path
    apple_client_id: str = ""  # Bundle ID
    google_client_id: str = ""

    model_config = {
        "env_file": f".env.{os.getenv('VAAKYA_ENV', 'dev')}",
        "extra": "ignore",
    }

settings = Settings()
```

- [ ] **Step 5: Remove redis dependency from pyproject.toml**

Remove `"redis>=7.4.0"` from dependencies in `pyproject.toml`. Run `uv lock` to update lockfile.

- [ ] **Step 6: Remove faster-whisper dependency**

Remove `"faster-whisper>=1.2.1"` from dependencies. Transcription is client-side now. Run `uv lock`.

- [ ] **Step 7: Delete server-side transcription**

Delete `src/vaakya/routers/transcribe.py` and `src/vaakya/services/transcription.py`.
Remove `transcribe` router from `src/vaakya/main.py`.
Delete `tests/test_transcribe.py`.

- [ ] **Step 8: Commit**

```bash
git add Dockerfile .github/ src/vaakya/config.py pyproject.toml
git commit -m "feat: deployment infrastructure — Dockerfile, GitHub Actions, config cleanup"
```

---

### Task 2: Real OAuth (Apple + Google)

**Files:**
- Create: `src/vaakya/services/oauth.py`
- Modify: `src/vaakya/routers/auth.py`
- Modify: `src/vaakya/schemas/auth.py`
- Modify: `tests/test_auth.py`
- Create: `VaakyaApp/Sources/Services/KeychainService.swift`
- Modify: `VaakyaApp/Sources/Views/LoginView.swift`
- Modify: `VaakyaApp/Sources/ViewModels/AuthViewModel.swift`
- Modify: `VaakyaApp/Sources/API/APIClient.swift`

- [ ] **Step 1: Create OAuth verification service**

```python
# src/vaakya/services/oauth.py
import httpx
from jose import jwt as jose_jwt
from jose.exceptions import JWTError

APPLE_JWKS_URL = "https://appleid.apple.com/auth/keys"
GOOGLE_TOKEN_URL = "https://oauth2.googleapis.com/tokeninfo"


async def verify_apple_identity_token(identity_token: str, client_id: str) -> dict:
    """Verify Apple Sign In identity token. Returns {'sub': ..., 'email': ..., 'name': ...}."""
    async with httpx.AsyncClient() as client:
        resp = await client.get(APPLE_JWKS_URL)
        resp.raise_for_status()
        jwks = resp.json()

    # Decode without verification first to get the key ID
    header = jose_jwt.get_unverified_header(identity_token)
    kid = header["kid"]

    # Find matching key
    key = next((k for k in jwks["keys"] if k["kid"] == kid), None)
    if not key:
        raise ValueError("Apple key not found")

    payload = jose_jwt.decode(
        identity_token,
        key,
        algorithms=["RS256"],
        audience=client_id,
        issuer="https://appleid.apple.com",
    )
    return {
        "sub": payload["sub"],
        "email": payload.get("email", ""),
    }


async def verify_google_id_token(id_token: str, client_id: str) -> dict:
    """Verify Google Sign In ID token. Returns {'sub': ..., 'email': ..., 'name': ...}."""
    async with httpx.AsyncClient() as client:
        resp = await client.get(f"{GOOGLE_TOKEN_URL}?id_token={id_token}")
        resp.raise_for_status()
        payload = resp.json()

    if payload.get("aud") != client_id:
        raise ValueError("Google token audience mismatch")

    return {
        "sub": payload["sub"],
        "email": payload.get("email", ""),
        "name": payload.get("name", ""),
        "avatar_url": payload.get("picture", ""),
    }
```

- [ ] **Step 2: Update auth schemas**

Modify `src/vaakya/schemas/auth.py`:

```python
from pydantic import BaseModel

class OAuthLoginRequest(BaseModel):
    provider: str  # "apple" or "google"
    identity_token: str  # The token from the provider
    name: str | None = None  # Apple only sends name on first sign-in

class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"

class RefreshRequest(BaseModel):
    refresh_token: str

class UserResponse(BaseModel):
    id: str
    email: str
    name: str
    provider: str
    avatar_url: str | None
```

- [ ] **Step 3: Rewrite auth router with real OAuth**

Replace `src/vaakya/routers/auth.py`:

```python
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, HTTPException
from jose import jwt
from sqlalchemy import select

from vaakya.config import settings
from vaakya.deps import DB, CurrentUser
from vaakya.models.user import User
from vaakya.schemas.auth import OAuthLoginRequest, TokenResponse, RefreshRequest, UserResponse
from vaakya.services.oauth import verify_apple_identity_token, verify_google_id_token

router = APIRouter(prefix="/auth", tags=["auth"])


def create_tokens(user_id: str) -> tuple[str, str]:
    now = datetime.now(timezone.utc)
    access = jwt.encode(
        {"sub": user_id, "exp": now + timedelta(minutes=settings.jwt_expire_minutes), "type": "access"},
        settings.jwt_secret,
        algorithm=settings.jwt_algorithm,
    )
    refresh = jwt.encode(
        {"sub": user_id, "exp": now + timedelta(minutes=settings.jwt_refresh_expire_minutes), "type": "refresh"},
        settings.jwt_secret,
        algorithm=settings.jwt_algorithm,
    )
    return access, refresh


@router.post("/login", response_model=TokenResponse)
async def login(body: OAuthLoginRequest, db: DB):
    if settings.vaakya_env == "dev":
        # Dev mode: skip verification, auto-create
        provider_sub = body.identity_token  # Use token as fake provider ID in dev
        email = f"dev-{provider_sub[:8]}@vaakya.dev"
        name = body.name or "Dev User"
        avatar_url = None
    elif body.provider == "apple":
        info = await verify_apple_identity_token(body.identity_token, settings.apple_client_id)
        provider_sub = info["sub"]
        email = info["email"]
        name = body.name or email.split("@")[0]
        avatar_url = None
    elif body.provider == "google":
        info = await verify_google_id_token(body.identity_token, settings.google_client_id)
        provider_sub = info["sub"]
        email = info["email"]
        name = info.get("name", email.split("@")[0])
        avatar_url = info.get("avatar_url")
    else:
        raise HTTPException(400, f"Unsupported provider: {body.provider}")

    result = await db.execute(
        select(User).where(User.provider == body.provider, User.provider_id == provider_sub)
    )
    user = result.scalar_one_or_none()

    if user is None:
        user = User(
            email=email,
            name=name,
            provider=body.provider,
            provider_id=provider_sub,
            avatar_url=avatar_url,
        )
        db.add(user)
        await db.commit()
        await db.refresh(user)

    access, refresh = create_tokens(user.id)
    return TokenResponse(access_token=access, refresh_token=refresh)


@router.post("/refresh", response_model=TokenResponse)
async def refresh(body: RefreshRequest):
    try:
        payload = jwt.decode(body.refresh_token, settings.jwt_secret, algorithms=[settings.jwt_algorithm])
        if payload.get("type") != "refresh":
            raise HTTPException(401, "Invalid token type")
        access, refresh = create_tokens(payload["sub"])
        return TokenResponse(access_token=access, refresh_token=refresh)
    except Exception:
        raise HTTPException(401, "Invalid refresh token")


@router.get("/me", response_model=UserResponse)
async def me(user: CurrentUser):
    return user
```

- [ ] **Step 4: Update test_auth.py for new schema**

Update `tests/test_auth.py` to use `OAuthLoginRequest` format with `provider` and `identity_token` fields. Test dev-mode auto-create, token refresh, and `/me` endpoint.

- [ ] **Step 5: Run backend tests**

```bash
cd /Users/nagarjuna/projects/meeting_genie && uv run pytest tests/ -v
```

Expected: All tests pass.

- [ ] **Step 6: Create KeychainService.swift**

```swift
// VaakyaApp/Sources/Services/KeychainService.swift
import Foundation
import Security

enum KeychainService {
    private static let service = "app.vaakya.auth"

    static func save(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
        var addQuery = query
        addQuery[kSecValueData as String] = data
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
```

- [ ] **Step 7: Update AuthViewModel for real OAuth + Keychain**

Modify `VaakyaApp/Sources/ViewModels/AuthViewModel.swift`:
- Replace UserDefaults token storage with `KeychainService`
- Add `signInWithApple()` method using `ASAuthorizationAppleIDProvider`
- Add `signInWithGoogle()` method using Google Sign-In SDK
- Add `refreshToken()` method calling `/auth/refresh`
- Store both access_token and refresh_token in Keychain
- On `checkSession()`: try loading token from Keychain, verify with `/auth/me`, refresh if expired

- [ ] **Step 8: Update LoginView with Apple + Google buttons**

Modify `VaakyaApp/Sources/Views/LoginView.swift`:
- Add `SignInWithAppleButton` (native SwiftUI component)
- Add Google Sign-In button
- Wire to `AuthViewModel.signInWithApple()` / `signInWithGoogle()`
- Style with new design system (light mode)

- [ ] **Step 9: Update APIClient for environment-aware base URL + Keychain**

Modify `VaakyaApp/Sources/API/APIClient.swift`:
- Base URL from build configuration: `#if DEBUG` → localhost, else → `https://api.vaakya.app`
- Load auth token from `KeychainService` instead of UserDefaults
- Add token refresh on 401 responses

- [ ] **Step 10: Update Package.swift for new dependencies**

Add to `VaakyaApp/Package.swift`:
- Platform: `.macOS(.v14), .iOS(.v17)`
- No external dependencies needed yet (Sign in with Apple is native, Google Sign-In added later or via SPM)

- [ ] **Step 11: Commit**

```bash
git commit -m "feat: real OAuth (Apple + Google) + Keychain + deployment"
```

---

## Phase 2: Core Features (Parallel)

> **All 4 tasks run simultaneously on separate worktrees.** No file conflicts — each touches different files.

### Task 3: Design System Overhaul

**Branch:** `feature/design-system`

**Files:**
- Create: `VaakyaApp/Sources/Theme/DesignTokens.swift`
- Create: `VaakyaApp/Sources/Theme/ThemeManager.swift`
- Create: `VaakyaApp/Sources/Views/PrivacyBadge.swift`
- Modify: `VaakyaApp/Sources/VaakyaApp.swift` (color palette, preferredColorScheme)
- Modify: `VaakyaApp/Sources/Views/MainView.swift`
- Modify: `VaakyaApp/Sources/Views/SidebarView.swift`
- Modify: `VaakyaApp/Sources/Views/MeetingDetailView.swift`
- Modify: `VaakyaApp/Sources/Views/BlockView.swift`
- Modify: `VaakyaApp/Sources/Views/ChatView.swift`
- Modify: `VaakyaApp/Sources/Views/TranscriptView.swift`
- Modify: `VaakyaApp/Sources/Views/SettingsView.swift`
- Modify: `VaakyaApp/Sources/Views/ShareSheet.swift`
- Modify: `VaakyaApp/Sources/Views/FloatingNotepad.swift`
- Modify: `VaakyaApp/Sources/Views/RecordingPillView.swift`

- [ ] **Step 1: Create DesignTokens.swift**

```swift
// VaakyaApp/Sources/Theme/DesignTokens.swift
import SwiftUI

enum VaakyaTheme {
    // MARK: - Colors (Light Mode)
    enum Light {
        static let bgApp = Color.white
        static let bgSidebar = Color(red: 0.969, green: 0.969, blue: 0.973) // #F7F7F8
        static let bgContent = Color.white
        static let bgCard = Color(red: 0.961, green: 0.961, blue: 0.969) // #F5F5F7
        static let bgHover = Color.black.opacity(0.04)
        static let bgActive = Color.black.opacity(0.06)
        static let bgAccent = Color(red: 0.204, green: 0.659, blue: 0.325).opacity(0.10)
        static let textPrimary = Color(red: 0.102, green: 0.102, blue: 0.102) // #1A1A1A
        static let textSecondary = Color(red: 0.420, green: 0.420, blue: 0.420) // #6B6B6B
        static let textTertiary = Color(red: 0.608, green: 0.608, blue: 0.608) // #9B9B9B
        static let accent = Color(red: 0.204, green: 0.659, blue: 0.325) // #34A853
        static let accentHover = Color(red: 0.176, green: 0.573, blue: 0.286) // #2D9249
        static let red = Color(red: 0.918, green: 0.263, blue: 0.208) // #EA4335
        static let blue = Color(red: 0.263, green: 0.522, blue: 0.957) // #4285F4
        static let yellow = Color(red: 0.984, green: 0.737, blue: 0.016) // #FBBC04
        static let border = Color.black.opacity(0.08)
        static let borderStrong = Color.black.opacity(0.15)
    }

    // MARK: - Colors (Dark Mode)
    enum Dark {
        static let bgApp = Color(red: 0.102, green: 0.102, blue: 0.102) // #1A1A1A
        static let bgSidebar = Color(red: 0.133, green: 0.133, blue: 0.133) // #222222
        static let bgContent = Color(red: 0.102, green: 0.102, blue: 0.102)
        static let bgCard = Color(red: 0.165, green: 0.165, blue: 0.165) // #2A2A2A
        static let textPrimary = Color(red: 0.929, green: 0.929, blue: 0.937) // #EDEDEF
        static let textSecondary = Color(red: 0.608, green: 0.608, blue: 0.608) // #9B9B9B
        static let accent = Color(red: 0.306, green: 0.796, blue: 0.443) // #4ECB71
    }

    // MARK: - Spacing
    static let space1: CGFloat = 4
    static let space2: CGFloat = 8
    static let space3: CGFloat = 12
    static let space4: CGFloat = 16
    static let space6: CGFloat = 24
    static let space8: CGFloat = 32
    static let space12: CGFloat = 48

    // MARK: - Radius
    static let radiusSm: CGFloat = 6
    static let radiusMd: CGFloat = 10
    static let radiusLg: CGFloat = 14
    static let radiusXl: CGFloat = 20

    // MARK: - Typography
    static let titleFont: Font = .system(size: 24, weight: .bold)
    static let headingFont: Font = .system(size: 16, weight: .semibold)
    static let bodyFont: Font = .system(size: 15)
    static let bodyMediumFont: Font = .system(size: 15, weight: .medium)
    static let captionFont: Font = .system(size: 13)
    static let labelFont: Font = .system(size: 12, weight: .medium)

    // MARK: - Block Colors
    static let summaryColor = Light.accent
    static let decisionColor = Light.blue
    static let actionColor = Light.red
    static let quoteColor = Light.yellow
}
```

- [ ] **Step 2: Create ThemeManager.swift**

```swift
// VaakyaApp/Sources/Theme/ThemeManager.swift
import SwiftUI

@Observable
final class ThemeManager {
    enum Appearance: String, CaseIterable {
        case light, dark, system
    }

    var appearance: Appearance = .light {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: "vaakya_appearance") }
    }

    var colorScheme: ColorScheme? {
        switch appearance {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }

    init() {
        if let saved = UserDefaults.standard.string(forKey: "vaakya_appearance"),
           let value = Appearance(rawValue: saved) {
            self.appearance = value
        }
    }
}
```

- [ ] **Step 3: Create PrivacyBadge.swift**

```swift
// VaakyaApp/Sources/Views/PrivacyBadge.swift
import SwiftUI

struct PrivacyBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "lock.fill")
                .font(.system(size: 10))
            #if os(macOS)
            Text("Processed on your Mac")
            #else
            Text("Processed on your iPhone")
            #endif
        }
        .font(VaakyaTheme.captionFont)
        .foregroundStyle(VaakyaTheme.Light.accent)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(VaakyaTheme.Light.bgAccent)
        .clipShape(RoundedRectangle(cornerRadius: VaakyaTheme.radiusSm))
    }
}
```

- [ ] **Step 4: Replace color palette in VaakyaApp.swift**

Remove old `extension Color { ... }` block with dark theme colors. Replace `.preferredColorScheme(.dark)` with dynamic theme from `ThemeManager`. Add `ThemeManager` as environment object.

- [ ] **Step 5: Update all views to use DesignTokens**

For each view file, replace:
- `Color.bgApp` → `VaakyaTheme.Light.bgApp` (or environment-aware)
- `Color.bgSidebar` → `VaakyaTheme.Light.bgSidebar`
- `Color.textPrimary` → `VaakyaTheme.Light.textPrimary`
- `Color.accent` → `VaakyaTheme.Light.accent`
- etc.

Update backgrounds to white/light gray. Update text to dark. Update spacing to use `VaakyaTheme.space*` constants. Update corner radii to `VaakyaTheme.radius*`. Update fonts to `VaakyaTheme.*Font`.

This is the largest step — systematically update: `MainView`, `SidebarView`, `MeetingDetailView`, `BlockView`, `ChatView`, `TranscriptView`, `SettingsView`, `ShareSheet`, `FloatingNotepad`, `RecordingPillView`.

**Key changes per view:**
- **SidebarView:** Light sidebar bg (#F7F7F8), green "+ New Note" button, meeting list items with more padding, source tags
- **MeetingDetailView:** White background, green accent for summary blocks, blue for decisions, red for actions, yellow for quotes. Max-width 720px. Privacy badge in metadata bar.
- **BlockView:** Light card background (#F5F5F7), soft shadow, 12px radius, 16px padding
- **TranscriptView:** Light background, colored speaker labels
- **SettingsView:** Tabbed horizontal layout (General, Recording, Calendar, AI, Transcription, Account). Green toggle switches.
- **LoginView:** Clean white background, centered form, Apple + Google sign in buttons

- [ ] **Step 6: Update SettingsView to tabbed layout**

Rewrite `SettingsView` with `TabView` or custom segmented control. Tabs: General, Recording, Calendar, AI Enhancement, Transcription, Account. Native toggle switches with green accent. Whisper model dropdown with download management.

- [ ] **Step 7: Build and verify**

```bash
cd VaakyaApp && swift build
```

Expected: Compiles without errors. Launch and verify light mode renders correctly.

- [ ] **Step 8: Commit**

```bash
git commit -m "feat: design system overhaul — light mode, green accent, Apple-native UX"
```

---

### Task 4: MLX Whisper On-Device Transcription

**Branch:** `feature/local-transcription`

**Files:**
- Create: `VaakyaApp/Sources/Services/TranscriptionService.swift`
- Create: `VaakyaApp/Sources/Services/ModelManager.swift`
- Modify: `VaakyaApp/Package.swift`
- Modify: `VaakyaApp/Sources/Services/AudioRecorder.swift`
- Modify: `VaakyaApp/Sources/ViewModels/MeetingViewModel.swift`

- [ ] **Step 1: Add mlx-swift dependencies to Package.swift**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Vaakya",
    platforms: [.macOS(.v14), .iOS(.v17)],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0"),
    ],
    targets: [
        .executableTarget(
            name: "Vaakya",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit"),
            ],
            path: "Sources",
            exclude: ["Resources"]
        )
    ]
)
```

WhisperKit wraps mlx-swift with a clean Swift API for Whisper. It handles model downloading, audio preprocessing, and streaming transcription. Verify the latest version at https://github.com/argmaxinc/WhisperKit before using.

- [ ] **Step 2: Resolve package and verify build**

```bash
cd VaakyaApp && swift package resolve && swift build
```

Expected: Dependencies resolve. Build succeeds (may take a few minutes for mlx-swift compilation).

- [ ] **Step 3: Create ModelManager.swift**

```swift
// VaakyaApp/Sources/Services/ModelManager.swift
import Foundation
import WhisperKit

@MainActor
@Observable
final class ModelManager {
    var availableModels: [String] = []
    var downloadedModels: [String] = []
    var downloadProgress: Double = 0
    var isDownloading = false
    var currentModel: String?

    private let modelsDirectory: URL = {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Vaakya/Models")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    var recommendedModel: String {
        let ram = ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024) // GB
        #if os(macOS)
        return ram >= 16 ? "large-v3-turbo" : "base"
        #else
        return ram >= 8 ? "small" : "base"
        #endif
    }

    var recommendedModelSize: String {
        switch recommendedModel {
        case "large-v3-turbo": return "1.6 GB"
        case "base": return "142 MB"
        case "small": return "466 MB"
        default: return "Unknown"
        }
    }

    func loadAvailableModels() async {
        do {
            availableModels = try await WhisperKit.fetchAvailableModels()
        } catch {
            availableModels = ["large-v3-turbo", "base", "small"]
        }
        refreshDownloaded()
    }

    func downloadModel(_ modelName: String) async throws {
        isDownloading = true
        downloadProgress = 0
        defer { isDownloading = false }

        // WhisperKit handles model download and caching
        let _ = try await WhisperKit(
            model: modelName,
            downloadBase: modelsDirectory.path,
            verbose: false
        )
        currentModel = modelName
        refreshDownloaded()
    }

    func deleteModel(_ modelName: String) throws {
        let modelPath = modelsDirectory.appendingPathComponent(modelName)
        try FileManager.default.removeItem(at: modelPath)
        refreshDownloaded()
        if currentModel == modelName { currentModel = nil }
    }

    func diskUsage() -> String {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: modelsDirectory, includingPropertiesForKeys: [.fileSizeKey]
        ) else { return "0 MB" }
        let bytes = contents.compactMap {
            try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize
        }.reduce(0, +)
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private func refreshDownloaded() {
        downloadedModels = (try? FileManager.default.contentsOfDirectory(atPath: modelsDirectory.path)) ?? []
    }
}
```

- [ ] **Step 4: Create TranscriptionService.swift**

```swift
// VaakyaApp/Sources/Services/TranscriptionService.swift
import Foundation
import WhisperKit

struct TranscriptSegment: Identifiable, Codable, Sendable {
    let id: String
    let start: Double      // seconds
    let end: Double         // seconds
    let text: String
    var speaker: String?    // filled by diarization

    init(start: Double, end: Double, text: String, speaker: String? = nil) {
        self.id = UUID().uuidString
        self.start = start
        self.end = end
        self.text = text
        self.speaker = speaker
    }

    var startFormatted: String { Self.formatTime(start) }
    var endFormatted: String { Self.formatTime(end) }

    private static func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

@MainActor
@Observable
final class TranscriptionService {
    var segments: [TranscriptSegment] = []
    var isTranscribing = false
    var progress: Double = 0
    var error: String?

    private var whisperKit: WhisperKit?

    /// Initialize with a specific model. Call once after model is downloaded.
    func loadModel(_ modelName: String, modelsDirectory: URL) async throws {
        whisperKit = try await WhisperKit(
            model: modelName,
            downloadBase: modelsDirectory.path,
            verbose: false
        )
    }

    /// Transcribe an audio file. Updates `segments` as results stream in.
    func transcribe(audioURL: URL) async throws {
        guard let kit = whisperKit else {
            throw TranscriptionError.modelNotLoaded
        }

        isTranscribing = true
        progress = 0
        segments = []
        error = nil
        defer { isTranscribing = false }

        let results = try await kit.transcribe(audioPath: audioURL.path)

        for result in results {
            for segment in result.segments {
                let seg = TranscriptSegment(
                    start: Double(segment.start),
                    end: Double(segment.end),
                    text: segment.text.trimmingCharacters(in: .whitespaces)
                )
                segments.append(seg)
            }
        }

        progress = 1.0
    }

    /// Convert segments to plain transcript text for API/storage
    func transcriptText() -> String {
        segments.map { seg in
            let speaker = seg.speaker.map { "[\($0)] " } ?? ""
            return "[\(seg.startFormatted)] \(speaker)\(seg.text)"
        }.joined(separator: "\n")
    }

    enum TranscriptionError: Error, LocalizedError {
        case modelNotLoaded
        var errorDescription: String? {
            switch self {
            case .modelNotLoaded: return "Whisper model not loaded. Download a model in Settings."
            }
        }
    }
}
```

- [ ] **Step 5: Update MeetingViewModel to use local transcription**

Modify `VaakyaApp/Sources/ViewModels/MeetingViewModel.swift`:
- Add `TranscriptionService` and `ModelManager` properties
- After `stopRecording()`, call `transcriptionService.transcribe(audioURL:)` locally
- Remove calls to server-side `/meetings/{id}/transcribe`
- Store transcript text in meeting via `PATCH /meetings/{id}` (for sync only)
- Show real-time progress during transcription

- [ ] **Step 6: Build and test**

```bash
cd VaakyaApp && swift build
```

Expected: Compiles. Test by recording a short audio clip and verifying transcript segments appear.

- [ ] **Step 7: Commit**

```bash
git commit -m "feat: MLX Whisper on-device transcription via WhisperKit"
```

---

### Task 5: pyannote Speaker Diarization

**Branch:** `feature/speaker-diarization`

**Files:**
- Create: `VaakyaApp/Sources/Services/DiarizationService.swift`
- Modify: `VaakyaApp/Package.swift` (add onnxruntime-swift)
- Modify: `VaakyaApp/Sources/API/Models.swift` (add Speaker model)
- Modify: `VaakyaApp/Sources/Views/TranscriptView.swift` (real speaker labels + filter)
- Modify: `VaakyaApp/Sources/Views/MeetingDetailView.swift` (speaker breakdown)
- Create: `VaakyaApp/Sources/Views/SpeakerMatchingView.swift`

- [ ] **Step 1: Add ONNX Runtime dependency**

Add to `Package.swift` dependencies:
```swift
.package(url: "https://github.com/nicklama/onnxruntime-swift-package-manager", from: "1.17.0"),
```

And in target dependencies:
```swift
.product(name: "onnxruntime", package: "onnxruntime-swift-package-manager"),
```

Note: Verify the latest package URL and version. The pyannote segmentation ONNX model (~17MB) needs to be bundled or downloaded at runtime. Check https://huggingface.co/pyannote/segmentation-3.0 for the ONNX export.

- [ ] **Step 2: Create DiarizationService.swift**

```swift
// VaakyaApp/Sources/Services/DiarizationService.swift
import Foundation

struct Speaker: Identifiable, Codable, Sendable {
    let id: String
    var label: String        // "Speaker 1" or user-assigned name
    var color: String        // hex color from palette
    var talkTimeSeconds: Double

    static let colors = ["#34A853", "#4285F4", "#EA4335", "#FBBC04", "#9C27B0", "#FF6D00", "#00BCD4", "#795548"]
}

@MainActor
@Observable
final class DiarizationService {
    var speakers: [Speaker] = []
    var isDiarizing = false
    var progress: Double = 0

    /// Run speaker diarization on audio file, then align with transcript segments.
    func diarize(audioURL: URL, segments: inout [TranscriptSegment]) async throws {
        isDiarizing = true
        progress = 0
        defer { isDiarizing = false }

        // Step 1: Run pyannote ONNX model to get speaker turns
        let turns = try await runPyannoteSegmentation(audioURL: audioURL)
        progress = 0.7

        // Step 2: Assign speaker labels
        var speakerMap: [String: Speaker] = [:]
        for (index, speakerId) in Set(turns.map(\.speakerId)).sorted().enumerated() {
            let color = Speaker.colors[index % Speaker.colors.count]
            speakerMap[speakerId] = Speaker(
                id: speakerId,
                label: "Speaker \(index + 1)",
                color: color,
                talkTimeSeconds: 0
            )
        }

        // Step 3: Align turns with transcript segments by timestamp overlap
        for i in segments.indices {
            let segMid = (segments[i].start + segments[i].end) / 2
            if let bestTurn = turns.first(where: { segMid >= $0.start && segMid <= $0.end }) {
                segments[i].speaker = speakerMap[bestTurn.speakerId]?.label
                speakerMap[bestTurn.speakerId]?.talkTimeSeconds += (segments[i].end - segments[i].start)
            }
        }

        speakers = Array(speakerMap.values).sorted { $0.talkTimeSeconds > $1.talkTimeSeconds }
        progress = 1.0
    }

    func renameSpeaker(id: String, newName: String, segments: inout [TranscriptSegment]) {
        guard let index = speakers.firstIndex(where: { $0.id == id }) else { return }
        let oldLabel = speakers[index].label
        speakers[index].label = newName
        for i in segments.indices where segments[i].speaker == oldLabel {
            segments[i].speaker = newName
        }
    }

    // MARK: - pyannote ONNX inference

    private struct SpeakerTurn {
        let start: Double
        let end: Double
        let speakerId: String
    }

    private func runPyannoteSegmentation(audioURL: URL) async throws -> [SpeakerTurn] {
        // Load ONNX model from app bundle or downloaded models directory
        // Run inference to get frame-level speaker probabilities
        // Post-process into speaker turns using peak detection + clustering
        //
        // Implementation notes:
        // 1. Load audio as 16kHz mono float array
        // 2. Run through pyannote segmentation-3.0 ONNX model
        //    - Input: [1, num_samples] float32
        //    - Output: [1, num_frames, num_speakers] float32 (speaker probabilities per frame)
        // 3. For each frame, assign speaker with highest probability
        // 4. Merge consecutive frames with same speaker into turns
        // 5. Apply minimum duration threshold (0.5s) to avoid micro-segments
        //
        // The ONNX Runtime Swift API:
        //   let env = try ORTEnv(loggingLevel: .warning)
        //   let session = try ORTSession(env: env, modelPath: modelPath, sessionOptions: nil)
        //   let input = try ORTValue(tensorData: audioData, elementType: .float, shape: shape)
        //   let output = try session.run(withInputs: ["input": input], outputNames: ["output"])

        // TODO: Full ONNX inference implementation.
        // This requires:
        // 1. Download pyannote segmentation-3.0 ONNX model (~17MB) via ModelManager
        // 2. Audio preprocessing: resample to 16kHz, convert to float32
        // 3. ONNX session creation and inference
        // 4. Post-processing of frame probabilities into speaker turns
        //
        // For the initial implementation, use the onnxruntime-swift bindings.
        // Reference: https://onnxruntime.ai/docs/get-started/with-swift.html

        fatalError("Implement ONNX inference — see implementation notes above")
    }
}
```

**Critical implementation note for the agent:** The `runPyannoteSegmentation` method needs a real ONNX Runtime implementation. The key steps are:
1. Use `ORTEnv` and `ORTSession` from onnxruntime-swift
2. Load audio file, convert to 16kHz mono float array (use AVAudioFile + AVAudioConverter)
3. Create ONNX tensor input
4. Run inference
5. Post-process output probabilities into SpeakerTurn array

Search for "pyannote onnx swift" or "onnxruntime swift speaker diarization" for reference implementations. The pyannote-audio Python library's source code shows the post-processing logic.

- [ ] **Step 3: Add Speaker model to Models.swift**

Add to `VaakyaApp/Sources/API/Models.swift`:

```swift
// MARK: - Speaker (local-only, not sent to server)

struct SpeakerInfo: Codable, Sendable, Identifiable {
    let id: String
    var label: String
    var color: String
    var talkTimeSeconds: Double

    var talkTimeFormatted: String {
        let mins = Int(talkTimeSeconds) / 60
        let secs = Int(talkTimeSeconds) % 60
        return "\(mins)m \(secs)s"
    }

    var talkTimePercent: Double // Set relative to total meeting duration
}
```

- [ ] **Step 4: Update TranscriptView with real speaker labels + filter**

Modify `VaakyaApp/Sources/Views/TranscriptView.swift`:
- Show speaker label (colored badge) on each segment
- Speaker colors match `Speaker.colors` palette
- Add speaker filter dropdown: "All Speakers" / individual speaker names
- When filtered, only show segments from selected speaker
- Click segment → seek audio to timestamp (existing behavior, now with speaker context)

- [ ] **Step 5: Add speaker breakdown to MeetingDetailView**

Add to `MeetingDetailView` metadata section:
- Speaker count: "3 speakers"
- Talk time breakdown: horizontal bar chart showing each speaker's percentage
- Each bar colored by speaker's assigned color
- Speaker names shown below bars

- [ ] **Step 6: Create SpeakerMatchingView.swift**

```swift
// VaakyaApp/Sources/Views/SpeakerMatchingView.swift
import SwiftUI

struct SpeakerMatchingView: View {
    let speakers: [Speaker]
    let participants: [String]  // Names from calendar event
    let audioURL: URL
    var onMatch: (String, String) -> Void  // (speakerId, participantName)
    var onDismiss: () -> Void

    // For each speaker, show a 5-second audio clip + list of participant names to tap
    // "Someone not on the invite" option for each
    // Done button when all matched
    var body: some View {
        // Implementation: VStack of speaker rows
        // Each row: play button (plays 5s audio sample), speaker label, participant buttons
        // After all matched, "Done" button dismisses and updates speakers
        Text("Speaker Matching — implement per spec")
    }
}
```

- [ ] **Step 7: Build and test**

```bash
cd VaakyaApp && swift build
```

Expected: Compiles (ONNX inference stub will fatalError at runtime until fully implemented).

- [ ] **Step 8: Commit**

```bash
git commit -m "feat: pyannote speaker diarization with ONNX Runtime"
```

---

### Task 6: Calendar / EventKit Integration

**Branch:** `feature/calendar`

**Files:**
- Create: `VaakyaApp/Sources/Services/CalendarService.swift`
- Create: `VaakyaApp/Sources/Services/MeetingSourceDetector.swift`
- Create: `VaakyaApp/Sources/ViewModels/CalendarViewModel.swift`
- Modify: `VaakyaApp/Sources/API/Models.swift` (add participants, source fields to Meeting)
- Modify: `VaakyaApp/Sources/VaakyaApp.swift` (menu bar overhaul)
- Modify: `src/vaakya/models/meeting.py` (add source, participants)
- Modify: `src/vaakya/schemas/meeting.py`

- [ ] **Step 1: Create CalendarService.swift**

```swift
// VaakyaApp/Sources/Services/CalendarService.swift
import EventKit
import Foundation

@MainActor
@Observable
final class CalendarService {
    var isAuthorized = false
    var upcomingEvents: [EKEvent] = []
    var nextEvent: EKEvent?

    private let store = EKEventStore()
    private var changeObserver: Any?

    func requestAccess() async {
        do {
            let granted = try await store.requestFullAccessToEvents()
            isAuthorized = granted
            if granted {
                loadUpcoming()
                watchForChanges()
            }
        } catch {
            isAuthorized = false
        }
    }

    func loadUpcoming() {
        let now = Date()
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: now)!
        let predicate = store.predicateForEvents(withStart: now, end: endOfDay, calendars: nil)
        upcomingEvents = store.events(matching: predicate)
            .filter { $0.endDate > now }
            .sorted { $0.startDate < $1.startDate }
        nextEvent = upcomingEvents.first
    }

    func participants(for event: EKEvent) -> [(name: String, email: String)] {
        (event.attendees ?? []).compactMap { attendee in
            guard let name = attendee.name,
                  let email = attendee.url.absoluteString
                    .replacingOccurrences(of: "mailto:", with: "")
                    .nilIfEmpty
            else { return nil }
            return (name: name, email: email)
        }
    }

    func videoLink(for event: EKEvent) -> URL? {
        // Check URL field, location, and notes for video links
        let candidates = [event.url?.absoluteString, event.location, event.notes]
            .compactMap { $0 }
            .joined(separator: " ")

        let patterns = [
            "https?://[\\w.-]*zoom\\.us/[\\w/?=&-]+",
            "https?://meet\\.google\\.com/[\\w-]+",
            "https?://teams\\.microsoft\\.com/[\\w/?=&-]+",
            "https?://[\\w.-]*webex\\.com/[\\w/?=&-]+",
        ]
        for pattern in patterns {
            if let range = candidates.range(of: pattern, options: .regularExpression) {
                return URL(string: String(candidates[range]))
            }
        }
        return nil
    }

    func suggestedTemplate(for event: EKEvent) -> String {
        let title = event.title.lowercased()
        if title.contains("standup") || title.contains("stand-up") || title.contains("daily") {
            return "standup"
        } else if title.contains("1:1") || title.contains("1-on-1") || title.contains("one on one") {
            return "one_on_one"
        } else if title.contains("interview") {
            return "interview"
        } else if title.contains("retro") {
            return "retrospective"
        } else if title.contains("sales") || title.contains("demo") {
            return "sales_call"
        }
        return "general"
    }

    private func watchForChanges() {
        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            self?.loadUpcoming()
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
```

- [ ] **Step 2: Create MeetingSourceDetector.swift**

```swift
// VaakyaApp/Sources/Services/MeetingSourceDetector.swift
import Foundation
#if os(macOS)
import AppKit
#endif

enum MeetingSource: String, Codable, Sendable {
    case zoom = "Zoom"
    case meet = "Meet"
    case teams = "Teams"
    case facetime = "FaceTime"
    case webex = "Webex"
    case inPerson = "In Person"
    case manual = "Manual"
}

enum MeetingSourceDetector {
    static func detect(calendarEvent: Any? = nil) -> MeetingSource {
        // Check calendar event URL first
        // (calendarEvent would be EKEvent, but kept as Any to avoid EventKit import here)

        #if os(macOS)
        // Check running processes
        let apps = NSWorkspace.shared.runningApplications.map { $0.bundleIdentifier ?? "" }
        if apps.contains("us.zoom.xos") { return .zoom }
        if apps.contains("com.microsoft.teams2") || apps.contains("com.microsoft.teams") { return .teams }
        if apps.contains("com.cisco.webexmeetingsapp") { return .webex }
        if apps.contains("com.apple.facetime") { return .facetime }
        // Check Chrome/Safari for Google Meet
        // (would need accessibility or AppleScript — simplified here)
        return .manual
        #else
        return .inPerson  // iOS is always in-person (mic only)
        #endif
    }

    static func detect(fromURL url: String) -> MeetingSource {
        let lower = url.lowercased()
        if lower.contains("zoom.us") { return .zoom }
        if lower.contains("meet.google.com") { return .meet }
        if lower.contains("teams.microsoft.com") { return .teams }
        if lower.contains("webex.com") { return .webex }
        return .manual
    }
}
```

- [ ] **Step 3: Create CalendarViewModel.swift**

```swift
// VaakyaApp/Sources/ViewModels/CalendarViewModel.swift
import EventKit
import Foundation
import UserNotifications

@MainActor
@Observable
final class CalendarViewModel {
    let calendarService = CalendarService()
    var autoStartEnabled = false {
        didSet { UserDefaults.standard.set(autoStartEnabled, forKey: "vaakya_auto_start") }
    }

    private var meetingCheckTimer: Timer?

    init() {
        autoStartEnabled = UserDefaults.standard.bool(forKey: "vaakya_auto_start")
    }

    func setup() async {
        await calendarService.requestAccess()
        startMeetingCheck()
    }

    /// Create a Meeting pre-populated from a calendar event
    func meetingFromEvent(_ event: EKEvent) -> (title: String, participants: [(name: String, email: String)], template: String, source: MeetingSource) {
        let participants = calendarService.participants(for: event)
        let template = calendarService.suggestedTemplate(for: event)
        let source: MeetingSource
        if let link = calendarService.videoLink(for: event) {
            source = MeetingSourceDetector.detect(fromURL: link.absoluteString)
        } else {
            source = MeetingSourceDetector.detect()
        }
        return (title: event.title, participants: participants, template: template, source: source)
    }

    private func startMeetingCheck() {
        meetingCheckTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkForUpcomingMeeting()
            }
        }
    }

    private func checkForUpcomingMeeting() {
        guard autoStartEnabled, let next = calendarService.nextEvent else { return }
        let timeUntil = next.startDate.timeIntervalSinceNow
        // Notify 1 minute before
        if timeUntil > 0 && timeUntil < 60 {
            sendMeetingNotification(event: next)
        }
    }

    private func sendMeetingNotification(event: EKEvent) {
        let content = UNMutableNotificationContent()
        content.title = "Meeting starting"
        content.body = "\(event.title ?? "Meeting") — tap to start recording"
        content.sound = .default
        let request = UNNotificationRequest(identifier: event.eventIdentifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
```

- [ ] **Step 4: Update Meeting model with source + participants**

Add to `VaakyaApp/Sources/API/Models.swift` Meeting struct:
```swift
let source: String?          // "Zoom", "Meet", "Teams", "In Person", "Manual"
let participants: String?    // JSON string of [{name, email}]
```

Add to backend `src/vaakya/models/meeting.py`:
```python
source: Mapped[str | None] = mapped_column(String(50), nullable=True)
participants_json: Mapped[str | None] = mapped_column(Text, nullable=True)
```

Create Alembic migration for the new columns.

Update `src/vaakya/schemas/meeting.py` to include `source` and `participants_json` fields.

- [ ] **Step 5: Overhaul menu bar in VaakyaApp.swift**

Replace the current menu bar with:
- Status: "No active meeting" or meeting name + timer when recording
- Show next upcoming meeting from CalendarViewModel (title, time, participant count)
- "Start Recording" button (⌘⇧R) — if calendar event exists, pre-populate
- "Show Vaakya" (⌘⌥M)
- "Meeting Library" (⌘⇧L)
- Divider
- Recent: last 3 meetings with real data from MeetingViewModel
- Divider
- "Audio never leaves your Mac" privacy badge
- "Quit Vaakya" (⌘Q)

- [ ] **Step 6: Build and test**

```bash
cd VaakyaApp && swift build
```

Expected: Compiles. Calendar permission dialog appears on launch. Upcoming events show in menu bar.

- [ ] **Step 7: Commit**

```bash
git commit -m "feat: calendar integration — EventKit, meeting source detection, menu bar"
```

---

## Phase 3: Integration (Parallel, after Phase 2 merge)

> Merge all Phase 2 branches to main first. Then start these 2 tasks in parallel.

### Task 7: iOS Platform Adaptation

**Branch:** `feature/ios-app`

**Files:**
- Create: `VaakyaApp/Sources/iOS/iOSMainView.swift`
- Create: `VaakyaApp/Sources/iOS/iOSRecordingView.swift`
- Create: `VaakyaApp/Sources/iOS/NextMeetingCard.swift`
- Create: `VaakyaApp/Sources/Services/AudioDeviceManager.swift`
- Create: `VaakyaApp/Sources/Services/AudioDeviceManagerIOS.swift`
- Modify: `VaakyaApp/Package.swift` (iOS target)
- Modify: `VaakyaApp/Sources/VaakyaApp.swift` (platform conditionals)
- Modify: `VaakyaApp/Sources/Services/AudioRecorder.swift` (background + devices)
- Modify: `VaakyaApp/Sources/Views/MainView.swift` (macOS-only guard)

- [ ] **Step 1: Update Package.swift for iOS**

Platform line becomes: `platforms: [.macOS(.v14), .iOS(.v17)]`

Ensure all dependencies support both platforms. WhisperKit supports iOS. ONNX Runtime supports iOS.

- [ ] **Step 2: Create iOSMainView.swift**

```swift
// VaakyaApp/Sources/iOS/iOSMainView.swift
#if os(iOS)
import SwiftUI

struct iOSMainView: View {
    @Environment(AuthViewModel.self) var auth
    @State private var viewModel = MeetingViewModel()
    @State private var selectedMeeting: Meeting?

    var body: some View {
        NavigationStack {
            List {
                // Next meeting card
                NextMeetingCard()

                // Meeting list
                ForEach(viewModel.meetings, id: \.id) { meeting in
                    NavigationLink(value: meeting) {
                        MeetingRow(meeting: meeting)
                    }
                }
            }
            .navigationTitle("Vaakya")
            .navigationDestination(for: Meeting.self) { meeting in
                MeetingDetailView(meeting: meeting)
            }
            .toolbar {
                Button(action: { /* new recording */ }) {
                    Image(systemName: "record.circle")
                        .foregroundStyle(VaakyaTheme.Light.red)
                }
            }
        }
    }
}
#endif
```

- [ ] **Step 3: Create AudioDeviceManager.swift (macOS)**

```swift
// VaakyaApp/Sources/Services/AudioDeviceManager.swift
#if os(macOS)
import CoreAudio
import Foundation

@MainActor
@Observable
final class AudioDeviceManager {
    struct AudioDevice: Identifiable, Sendable {
        let id: AudioDeviceID
        let name: String
        let isInput: Bool
    }

    var inputDevices: [AudioDevice] = []
    var selectedInputDevice: AudioDevice?

    func loadDevices() { /* CoreAudio AudioObjectGetPropertyData */ }
    func selectDevice(_ device: AudioDevice) { /* Set as active input */ }
    func watchForChanges() { /* AudioObjectAddPropertyListener */ }
    func handleDisconnect() { /* Auto-fallback to next available */ }
}
#endif
```

- [ ] **Step 4: Create AudioDeviceManagerIOS.swift**

```swift
// VaakyaApp/Sources/Services/AudioDeviceManagerIOS.swift
#if os(iOS)
import AVFoundation
import Foundation

@MainActor
@Observable
final class AudioDeviceManagerIOS {
    struct AudioInput: Identifiable, Sendable {
        let id: String
        let name: String
        let portType: AVAudioSession.Port
    }

    var availableInputs: [AudioInput] = []
    var currentInput: AudioInput?

    func loadInputs() {
        availableInputs = AVAudioSession.sharedInstance().availableInputs?.map {
            AudioInput(id: $0.uid, name: $0.portName, portType: $0.portType)
        } ?? []
        currentInput = availableInputs.first
    }

    func selectInput(_ input: AudioInput) throws {
        if let port = AVAudioSession.sharedInstance().availableInputs?.first(where: { $0.uid == input.id }) {
            try AVAudioSession.sharedInstance().setPreferredInput(port)
        }
    }

    func watchForRouteChanges() {
        NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.loadInputs()
        }
    }
}
#endif
```

- [ ] **Step 5: Update AudioRecorder for iOS background recording**

Modify `VaakyaApp/Sources/Services/AudioRecorder.swift`:
- Add `#if os(iOS)` section to configure `AVAudioSession` for background recording
- Set category `.record`, mode `.default`, options `.allowBluetooth`
- Activate session with `.notifyOthersOnDeactivation`
- Haptic feedback on record start/stop (`UIImpactFeedbackGenerator`)

- [ ] **Step 6: Add platform conditionals to VaakyaApp.swift**

```swift
@main
struct VaakyaApp: App {
    var body: some Scene {
        #if os(macOS)
        // Existing WindowGroup + MenuBarExtra
        #else
        WindowGroup {
            if auth.isLoggedIn {
                iOSMainView().environment(auth)
            } else {
                LoginView().environment(auth)
            }
        }
        #endif
    }
}
```

- [ ] **Step 7: Create NextMeetingCard.swift for iOS**

```swift
#if os(iOS)
struct NextMeetingCard: View {
    @Environment(CalendarViewModel.self) var calendar

    var body: some View {
        if let event = calendar.calendarService.nextEvent {
            // Card showing: event title, time, participant count, "Tap to record" button
        }
    }
}
#endif
```

- [ ] **Step 8: Add lock screen controls**

In `AudioRecorder`, when recording starts on iOS:
- Set `MPNowPlayingInfoCenter.default().nowPlayingInfo` with meeting title + duration
- Register for `MPRemoteCommandCenter` play/pause to control recording

- [ ] **Step 9: Build for both platforms**

```bash
cd VaakyaApp && swift build  # macOS
# For iOS, use xcodebuild or build via Xcode
```

- [ ] **Step 10: Commit**

```bash
git commit -m "feat: iOS app — NavigationStack, background recording, device management"
```

---

### Task 8: Dashboard + UX Patterns

**Branch:** `feature/dashboard`

**Files:**
- Create: `VaakyaApp/Sources/Views/DashboardView.swift`
- Create: `VaakyaApp/Sources/Views/ContextualSidebar.swift`
- Modify: `VaakyaApp/Sources/Views/MainView.swift` (dashboard as default view)
- Modify: `VaakyaApp/Sources/Views/SidebarView.swift` (source tags)
- Modify: `VaakyaApp/Sources/Views/MeetingDetailView.swift` (contextual sidebar)

- [ ] **Step 1: Create DashboardView.swift**

```swift
// VaakyaApp/Sources/Views/DashboardView.swift
import SwiftUI

struct DashboardView: View {
    @Environment(MeetingViewModel.self) var viewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VaakyaTheme.space6) {
                // Greeting
                Text("Good morning")  // Time-aware greeting
                    .font(VaakyaTheme.titleFont)
                    .foregroundStyle(VaakyaTheme.Light.textPrimary)
                Text("Here's your meeting overview")
                    .font(VaakyaTheme.bodyFont)
                    .foregroundStyle(VaakyaTheme.Light.textSecondary)

                // Stats cards — 4 in a row
                HStack(spacing: VaakyaTheme.space4) {
                    StatCard(icon: "chart.bar.fill", value: "\(meetingsThisWeek)", label: "Meetings this week", color: VaakyaTheme.Light.accent)
                    StatCard(icon: "clock.fill", value: totalCaptured, label: "Total captured", color: VaakyaTheme.Light.blue)
                    StatCard(icon: "checkmark.circle.fill", value: "\(actionItems)", label: "Action items", color: VaakyaTheme.Light.red)
                    StatCard(icon: "sparkles", value: "\(aiEnhanced)", label: "AI enhanced", color: VaakyaTheme.Light.accent)
                }

                // Quick Start
                Text("QUICK START")
                    .font(VaakyaTheme.labelFont)
                    .foregroundStyle(VaakyaTheme.Light.textTertiary)
                HStack(spacing: VaakyaTheme.space4) {
                    QuickStartCard(icon: "mic.fill", title: "Record meeting", subtitle: "Start capturing now")
                    QuickStartCard(icon: "magnifyingglass", title: "Search notes", subtitle: "Find across meetings")
                    QuickStartCard(icon: "checkmark.square", title: "Action items", subtitle: "Review pending tasks")
                }

                // Recently Enhanced
                Text("RECENTLY ENHANCED")
                    .font(VaakyaTheme.labelFont)
                    .foregroundStyle(VaakyaTheme.Light.textTertiary)
                ForEach(viewModel.meetings.prefix(5), id: \.id) { meeting in
                    RecentMeetingRow(meeting: meeting)
                }
            }
            .padding(VaakyaTheme.space8)
            .frame(maxWidth: 720)
        }
        .frame(maxWidth: .infinity)
        .background(VaakyaTheme.Light.bgContent)
    }

    // Computed properties for stats from viewModel.meetings
    private var meetingsThisWeek: Int { /* count meetings from this week */ 0 }
    private var totalCaptured: String { /* sum duration_seconds, format as "X.Xh" */ "0h" }
    private var actionItems: Int { /* count blocks where type == "action" && !is_checked */ 0 }
    private var aiEnhanced: Int { /* count meetings with AI-generated blocks */ 0 }
}

struct StatCard: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: VaakyaTheme.space2) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.system(size: 14))
            Text(value)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(VaakyaTheme.Light.textPrimary)
            Text(label)
                .font(VaakyaTheme.captionFont)
                .foregroundStyle(VaakyaTheme.Light.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(VaakyaTheme.space4)
        .background(VaakyaTheme.Light.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: VaakyaTheme.radiusMd))
    }
}

struct QuickStartCard: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: VaakyaTheme.space2) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(VaakyaTheme.Light.textSecondary)
            Text(title)
                .font(VaakyaTheme.bodyMediumFont)
                .foregroundStyle(VaakyaTheme.Light.textPrimary)
            Text(subtitle)
                .font(VaakyaTheme.captionFont)
                .foregroundStyle(VaakyaTheme.Light.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(VaakyaTheme.space4)
        .background(VaakyaTheme.Light.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: VaakyaTheme.radiusMd))
    }
}
```

- [ ] **Step 2: Create ContextualSidebar.swift**

```swift
// VaakyaApp/Sources/Views/ContextualSidebar.swift
import SwiftUI

struct ContextualSidebar: View {
    let meeting: Meeting
    @Environment(MeetingViewModel.self) var viewModel

    @State private var chatInput = ""
    @State private var chatResponse: String?

    var body: some View {
        VStack(alignment: .leading, spacing: VaakyaTheme.space6) {
            // Share Notes section
            Text("SHARE NOTES")
                .font(VaakyaTheme.labelFont)
                .foregroundStyle(VaakyaTheme.Light.textTertiary)

            Button(action: { /* copy rich text */ }) {
                Label("Copy text", systemImage: "doc.on.doc")
            }
            Button(action: { /* email */ }) {
                Label("Email", systemImage: "envelope")
            }
            Button(action: { /* slack format */ }) {
                Label("Copy for Slack", systemImage: "message")
            }

            Divider()

            // Ask Vaakya section
            Text("ASK VAAKYA")
                .font(VaakyaTheme.labelFont)
                .foregroundStyle(VaakyaTheme.Light.textTertiary)

            Button("List action items") { sendQuickAction("List all action items from this meeting") }
            Button("Write follow-up") { sendQuickAction("Write a follow-up email based on this meeting") }
            Button("Summarize") { sendQuickAction("Summarize this meeting in 3 bullet points") }

            if let response = chatResponse {
                Text(response)
                    .font(VaakyaTheme.bodyFont)
                    .foregroundStyle(VaakyaTheme.Light.textPrimary)
                    .padding(VaakyaTheme.space3)
                    .background(VaakyaTheme.Light.bgCard)
                    .clipShape(RoundedRectangle(cornerRadius: VaakyaTheme.radiusMd))
            }

            Spacer()

            // Chat input
            HStack {
                TextField("Ask about the meeting...", text: $chatInput)
                    .textFieldStyle(.plain)
                Button(action: { sendQuickAction(chatInput); chatInput = "" }) {
                    Image(systemName: "arrow.up.circle.fill")
                        .foregroundStyle(VaakyaTheme.Light.accent)
                }
                .disabled(chatInput.isEmpty)
            }
            .padding(VaakyaTheme.space3)
            .background(VaakyaTheme.Light.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: VaakyaTheme.radiusMd))
        }
        .padding(VaakyaTheme.space4)
        .frame(width: 240)
    }

    private func sendQuickAction(_ message: String) {
        Task {
            let result = try? await viewModel.chat(meetingId: meeting.id, message: message)
            chatResponse = result
        }
    }
}
```

- [ ] **Step 3: Update MainView to show dashboard by default**

When no meeting is selected, show `DashboardView` instead of an empty detail area.

- [ ] **Step 4: Add source tags to SidebarView**

Each meeting row shows a colored tag: "Zoom" (blue), "Meet" (green), "Teams" (purple), "In Person" (orange), "Manual" (gray). Tag positioned after duration.

- [ ] **Step 5: Replace ChatView with ContextualSidebar in MeetingDetailView**

Remove separate chat panel toggle. Instead, always show `ContextualSidebar` on the right side of MeetingDetailView. The transcript panel now toggles *below* the sidebar, not replacing it.

- [ ] **Step 6: Build and verify**

```bash
cd VaakyaApp && swift build
```

- [ ] **Step 7: Commit**

```bash
git commit -m "feat: dashboard, contextual sidebar, meeting source tags"
```

---

## Phase 4: Polish (Parallel)

> All 4 tasks run simultaneously. No file conflicts.

### Task 9: Web Share Viewer

**Branch:** `feature/share-viewer`

**Files:**
- Create: `share-viewer/index.html`
- Create: `share-viewer/styles.css`
- Create: `share-viewer/app.js`

- [ ] **Step 1: Create index.html**

Single-page app that:
- Reads token from URL path (`/TOKEN`)
- Fetches `GET /api/share/{token}` from the API
- Renders meeting title, date, participants, speaker breakdown
- Renders all blocks with Vaakya design system (light mode, green accent, colored borders)
- Shows "Get Vaakya" CTA at bottom with App Store link
- Handles expired links with clean message
- Responsive — looks good on mobile too

- [ ] **Step 2: Create styles.css**

Port the Vaakya design tokens to CSS:
```css
:root {
    --bg-app: #FFFFFF;
    --bg-card: #F5F5F7;
    --text-primary: #1A1A1A;
    --text-secondary: #6B6B6B;
    --accent: #34A853;
    --red: #EA4335;
    --blue: #4285F4;
    --yellow: #FBBC04;
    --radius-md: 10px;
    --radius-lg: 14px;
    --shadow-card: 0 1px 3px rgba(0,0,0,0.08);
}
```

Block rendering with colored left borders matching the app.

- [ ] **Step 3: Create app.js**

```javascript
const token = window.location.pathname.split('/').pop();
fetch(`${API_BASE}/api/share/${token}`)
    .then(r => r.ok ? r.json() : Promise.reject(r.status))
    .then(data => render(data))
    .catch(err => {
        if (err === 404 || err === 410) showExpired();
        else showError();
    });
```

- [ ] **Step 4: Commit**

```bash
git commit -m "feat: web share viewer — static SPA for shared meeting notes"
```

---

### Task 10: Onboarding Flow

**Branch:** `feature/onboarding`

**Files:**
- Create: `VaakyaApp/Sources/Views/OnboardingView.swift`
- Modify: `VaakyaApp/Sources/VaakyaApp.swift` (show onboarding on first launch)

- [ ] **Step 1: Create OnboardingView.swift**

Multi-step onboarding flow:
1. **Welcome:** "Welcome to Vaakya" — app icon, tagline
2. **Permissions:** Microphone, System Audio (macOS), Calendar — each with plain language explanation and a grant button. Show checkmarks as granted.
3. **Model Download:** Whisper model download with progress bar, size info, "This enables private on-device transcription — audio never leaves your device."
4. **Quick Tour:** 3-4 cards showing key features: menu bar, floating notepad, enhance, transcript
5. **Done:** "You're all set!" — button to dismiss and start

Track completion with `UserDefaults.standard.bool(forKey: "vaakya_onboarding_complete")`.

- [ ] **Step 2: Wire into VaakyaApp.swift**

After login, check onboarding flag. If not complete, show `OnboardingView` instead of `MainView`.

- [ ] **Step 3: Commit**

```bash
git commit -m "feat: onboarding flow — permissions, model download, quick tour"
```

---

### Task 11: Floating Pill Hardening

**Branch:** `feature/pill-hardening`

**Files:**
- Modify: `VaakyaApp/Sources/Views/FloatingNotepad.swift`
- Modify: `VaakyaApp/Sources/Views/RecordingPillView.swift`
- Modify: `VaakyaApp/Sources/Services/FloatingPanelManager.swift`

- [ ] **Step 1: Fix NSPanel window management**

In `FloatingPanelManager.swift`:
- Set `panel.styleMask = [.borderless, .nonactivatingPanel]`
- Set `panel.level = .floating` (or `.screenSaver` for fullscreen app compatibility)
- Set `panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`
- Explicitly disable: `panel.titlebarAppearsTransparent = true`, no toolbar, no tab bar
- Set `panel.tabbingMode = .disallowed`
- Remove any `toggleTabBar` hacks — set properties correctly from the start

- [ ] **Step 2: Pill states**

RecordingPillView shows:
- Red recording dot (pulsing animation)
- Timer (MM:SS)
- Audio waveform (3-bar animation using `currentAmplitude`)
- Current speaker name (from diarization, if running)
- Drag handle — pill is draggable via `.gesture(DragGesture())`

- [ ] **Step 3: Smooth pill ↔ notepad transition**

On `Cmd+Shift+V`:
- Animate frame size change from pill (200x40) to notepad (400x300) using `withAnimation(.spring(duration: 0.25))`
- Content crossfades between pill view and notepad view

- [ ] **Step 4: Test across apps**

Manually test floating pill with:
- Zoom in fullscreen
- Google Meet in Chrome fullscreen
- Microsoft Teams
- FaceTime
- Safari fullscreen

Verify pill stays visible and responsive in all cases.

- [ ] **Step 5: Commit**

```bash
git commit -m "fix: floating pill hardening — proper NSPanel config, fullscreen compat"
```

---

### Task 12: Error / Empty / Loading States

**Branch:** `feature/states`

**Files:**
- Modify: `VaakyaApp/Sources/Views/MainView.swift`
- Modify: `VaakyaApp/Sources/Views/MeetingDetailView.swift`
- Modify: `VaakyaApp/Sources/Views/TranscriptView.swift`
- Modify: `VaakyaApp/Sources/Views/SidebarView.swift`

- [ ] **Step 1: Empty states**

- **No meetings yet:** Illustration + "Record your first meeting" button
- **No transcript yet:** "Start recording to generate a transcript"
- **No enhanced notes yet:** "Click Enhance to create structured notes"
- **No blocks:** "Notes will appear here after enhancement"

Each empty state: centered icon, heading, subtitle, optional action button. Using design system colors.

- [ ] **Step 2: Loading states**

- **Transcription in progress:** "Transcribing..." with progress bar and percentage
- **Enhancement in progress:** "Enhancing notes..." with spinner
- **Sync in progress:** Small spinner in toolbar

- [ ] **Step 3: Error states**

- **No mic permission:** Alert with "Open System Preferences" button
- **Model download failed:** Retry button + error message
- **Cloud AI key invalid:** Redirect to Settings with highlighted field
- **Network offline during cloud enhance:** "You're offline. Use local AI (Ollama) or try again when connected."
- **API error:** Toast notification at top with error message, auto-dismiss after 5s

- [ ] **Step 4: Commit**

```bash
git commit -m "feat: error, empty, and loading states across all views"
```

---

## Phase 5: Final

### Task 13: TestFlight Readiness + E2E

**Branch:** `feature/testflight`

**Files:**
- Modify: `VaakyaApp/Package.swift` (final dependency check)
- Modify: `VaakyaApp/Sources/E2ETest.swift` (update for new flows)
- Create: `VaakyaApp/Info.plist` (if not using generated)

- [ ] **Step 1: Update E2E test suite**

Update `E2ETest.swift` to test:
- Health check
- OAuth login (dev mode)
- Meeting CRUD
- Block CRUD
- Enhancement
- Share link creation
- Settings CRUD
- New: verify local transcription path doesn't call server
- New: verify speaker data model

- [ ] **Step 2: Run full test suite**

```bash
# Backend
cd /Users/nagarjuna/projects/meeting_genie && uv run pytest tests/ -v

# Swift build
cd VaakyaApp && swift build

# E2E (requires backend running)
make e2e
```

Expected: All tests pass on both platforms.

- [ ] **Step 3: Privacy + App Store metadata**

Prepare:
- Privacy nutrition labels: microphone (required), calendar (optional), no tracking
- App Review notes explaining Screen Recording permission (macOS system audio capture)
- App description, screenshots, keywords for App Store listing
- App icon (if not already created)

- [ ] **Step 4: TestFlight setup**

- Create App Store Connect record for Vaakya
- Configure provisioning profiles for macOS + iOS
- Archive and upload via Xcode or `xcodebuild`
- Add beta testers

- [ ] **Step 5: Final smoke test**

Complete flow, no notes, no cheating:
1. Fresh install (delete app data)
2. Onboarding completes successfully
3. Grant all permissions
4. Model downloads
5. Start recording from menu bar
6. Talk for 2 minutes with another person
7. Stop recording → transcription completes
8. Speaker labels appear
9. Enhance notes → blocks appear with speaker attribution
10. Open transcript → click segment → audio seeks
11. Share link → open in browser → renders correctly
12. No crashes, no broken states

- [ ] **Step 6: Commit + tag**

```bash
git commit -m "feat: TestFlight readiness — E2E tests, app metadata"
git tag v0.1.0-beta.1
```

---

## Quick Reference: File Ownership by Task

Prevents merge conflicts when running parallel agents.

| File | Task |
|---|---|
| `Theme/DesignTokens.swift`, `Theme/ThemeManager.swift` | 3 |
| `Views/PrivacyBadge.swift` | 3 |
| All existing view files (design updates) | 3 |
| `Services/TranscriptionService.swift`, `Services/ModelManager.swift` | 4 |
| `Services/DiarizationService.swift`, `Views/SpeakerMatchingView.swift` | 5 |
| `Services/CalendarService.swift`, `Services/MeetingSourceDetector.swift`, `ViewModels/CalendarViewModel.swift` | 6 |
| `iOS/*`, `Services/AudioDeviceManager*.swift` | 7 |
| `Views/DashboardView.swift`, `Views/ContextualSidebar.swift` | 8 |
| `share-viewer/*` | 9 |
| `Views/OnboardingView.swift` | 10 |
| `Views/FloatingNotepad.swift`, `Views/RecordingPillView.swift`, `Services/FloatingPanelManager.swift` | 11 |
| Empty/error/loading states in existing views | 12 |
| `E2ETest.swift`, TestFlight config | 13 |

**Conflict risk:** Task 3 (design system) and Task 12 (states) both modify existing views. Run Task 12 after Task 3 merges. Tasks 4, 5, 6 create new files only — no conflicts with each other or Task 3.
