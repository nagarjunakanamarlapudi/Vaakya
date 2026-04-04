# Vaakya Backend API — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Vaakya backend API — auth, meetings, notes, AI enhancement, sharing, and sync — running fully local in dev via Docker Compose with PostgreSQL, Redis, and MinIO.

**Architecture:** FastAPI async server with SQLAlchemy 2.0 async ORM, PostgreSQL for persistence, Redis for caching/pub-sub, MinIO (S3-compatible) for file storage. Three environments: dev (all local), stg (AWS pre-prod), prod (AWS). Config-driven environment switching via `.env` files.

**Tech Stack:** Python 3.12+, uv, FastAPI, SQLAlchemy 2.0 (async), asyncpg, Redis, PostgreSQL, MinIO, Alembic, pytest, Docker Compose.

---

## File Structure

```
meeting_genie/
├── pyproject.toml                    # uv project config, dependencies
├── uv.lock                           # lockfile (auto-generated)
├── .python-version                   # pin Python version
├── .env.dev                          # dev environment vars
├── .env.stg                          # stg environment vars (gitignored)
├── .env.prod                         # prod environment vars (gitignored)
├── .gitignore
├── docker-compose.yml                # PostgreSQL, Redis, MinIO for dev
├── Makefile                          # dev commands (up, down, migrate, test, seed)
├── alembic.ini                       # Alembic config
├── alembic/
│   ├── env.py                        # migration environment
│   └── versions/                     # migration files
├── src/
│   └── vaakya/
│       ├── __init__.py
│       ├── main.py                   # FastAPI app factory, lifespan, router mount
│       ├── config.py                 # Settings from env vars (pydantic-settings)
│       ├── db.py                     # Async engine, session factory
│       ├── deps.py                   # FastAPI dependency injection (get_db, get_current_user)
│       ├── models/
│       │   ├── __init__.py
│       │   ├── base.py              # SQLAlchemy declarative base, common mixins
│       │   ├── user.py              # User model
│       │   ├── meeting.py           # Meeting model
│       │   ├── note.py              # Note + Block models
│       │   └── share.py             # ShareLink model
│       ├── schemas/
│       │   ├── __init__.py
│       │   ├── auth.py              # Auth request/response schemas
│       │   ├── meeting.py           # Meeting schemas
│       │   ├── note.py              # Note + Block schemas
│       │   └── share.py             # Share schemas
│       ├── routers/
│       │   ├── __init__.py
│       │   ├── auth.py              # POST /auth/login, /auth/refresh
│       │   ├── meetings.py          # CRUD /meetings
│       │   ├── notes.py             # CRUD /meetings/{id}/notes, blocks
│       │   ├── enhance.py           # POST /meetings/{id}/enhance
│       │   ├── share.py             # POST /notes/{id}/share, GET /share/{token}
│       │   └── health.py            # GET /health
│       ├── services/
│       │   ├── __init__.py
│       │   ├── ai.py                # AI enhancement (platform/byok/ollama routing)
│       │   └── storage.py           # S3/MinIO file operations
│       └── seed.py                  # Seed data for dev
├── tests/
│   ├── conftest.py                  # Fixtures: test db, test client, auth headers
│   ├── test_health.py
│   ├── test_auth.py
│   ├── test_meetings.py
│   ├── test_notes.py
│   ├── test_enhance.py
│   └── test_share.py
└── docs/
    └── superpowers/
        ├── specs/
        └── plans/
```

---

### Task 1: Project Scaffold + Docker Compose

**Files:**
- Create: `pyproject.toml`
- Create: `.python-version`
- Create: `.gitignore`
- Create: `.env.dev`
- Create: `docker-compose.yml`
- Create: `Makefile`
- Create: `src/vaakya/__init__.py`
- Create: `src/vaakya/main.py`
- Create: `src/vaakya/config.py`

- [ ] **Step 1: Initialize uv project**

```bash
cd /Users/nagarjuna/projects/meeting_genie
uv init --lib --name vaakya --package
```

- [ ] **Step 2: Set Python version**

```bash
echo "3.12" > .python-version
```

- [ ] **Step 3: Add dependencies**

```bash
uv add fastapi uvicorn[standard] sqlalchemy[asyncio] asyncpg alembic pydantic-settings redis python-jose[cryptography] passlib[bcrypt] httpx boto3 python-multipart
uv add --dev pytest pytest-asyncio httpx
```

- [ ] **Step 4: Create .gitignore**

Write `.gitignore`:
```
__pycache__/
*.pyc
.env.stg
.env.prod
.venv/
*.egg-info/
dist/
.superpowers/
```

- [ ] **Step 5: Create .env.dev**

Write `.env.dev`:
```bash
VAAKYA_ENV=dev
DATABASE_URL=postgresql+asyncpg://vaakya:vaakya@localhost:5432/vaakya
REDIS_URL=redis://localhost:6379/0
S3_ENDPOINT_URL=http://localhost:9000
S3_ACCESS_KEY=minioadmin
S3_SECRET_KEY=minioadmin
S3_BUCKET=vaakya-dev
JWT_SECRET=dev-secret-change-in-prod
JWT_ALGORITHM=HS256
JWT_EXPIRE_MINUTES=1440
AI_PROVIDER=ollama
OLLAMA_BASE_URL=http://localhost:11434
```

- [ ] **Step 6: Create docker-compose.yml**

Write `docker-compose.yml`:
```yaml
services:
  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_USER: vaakya
      POSTGRES_PASSWORD: vaakya
      POSTGRES_DB: vaakya
    ports:
      - "5432:5432"
    volumes:
      - pgdata:/var/lib/postgresql/data

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"

  minio:
    image: minio/minio
    command: server /data --console-address ":9001"
    environment:
      MINIO_ROOT_USER: minioadmin
      MINIO_ROOT_PASSWORD: minioadmin
    ports:
      - "9000:9000"
      - "9001:9001"
    volumes:
      - miniodata:/data

volumes:
  pgdata:
  miniodata:
```

- [ ] **Step 7: Create Makefile**

Write `Makefile`:
```makefile
.PHONY: up down dev test migrate seed

up:
	docker compose up -d

down:
	docker compose down

dev:
	uv run uvicorn vaakya.main:app --reload --env-file .env.dev --port 8000

test:
	uv run pytest -v

migrate:
	uv run alembic upgrade head

seed:
	uv run python -m vaakya.seed
```

- [ ] **Step 8: Create config.py**

Write `src/vaakya/config.py`:
```python
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    vaakya_env: str = "dev"
    database_url: str
    redis_url: str = "redis://localhost:6379/0"
    s3_endpoint_url: str = "http://localhost:9000"
    s3_access_key: str = "minioadmin"
    s3_secret_key: str = "minioadmin"
    s3_bucket: str = "vaakya-dev"
    jwt_secret: str = "dev-secret-change-in-prod"
    jwt_algorithm: str = "HS256"
    jwt_expire_minutes: int = 1440
    ai_provider: str = "ollama"
    ollama_base_url: str = "http://localhost:11434"

    model_config = {"env_file": ".env.dev", "extra": "ignore"}


settings = Settings()
```

- [ ] **Step 9: Create main.py**

Write `src/vaakya/main.py`:
```python
from contextlib import asynccontextmanager

from fastapi import FastAPI

from vaakya.config import settings
from vaakya.db import engine


@asynccontextmanager
async def lifespan(app: FastAPI):
    yield
    await engine.dispose()


app = FastAPI(
    title="Vaakya API",
    version="0.1.0",
    lifespan=lifespan,
)


@app.get("/health")
async def health():
    return {"status": "ok", "env": settings.vaakya_env}
```

- [ ] **Step 10: Create db.py stub**

Write `src/vaakya/db.py`:
```python
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine

from vaakya.config import settings

engine = create_async_engine(settings.database_url, echo=(settings.vaakya_env == "dev"))
async_session = async_sessionmaker(engine, expire_on_commit=False)
```

- [ ] **Step 11: Start services and verify**

```bash
make up
sleep 3
uv run uvicorn vaakya.main:app --env-file .env.dev --port 8000 &
sleep 2
curl -s http://localhost:8000/health | python -m json.tool
kill %1
```

Expected: `{"status": "ok", "env": "dev"}`

- [ ] **Step 12: Commit**

```bash
git init
git add -A
git commit -m "feat: project scaffold with FastAPI, Docker Compose, uv"
```

---

### Task 2: Database Models + Alembic Migrations

**Files:**
- Create: `src/vaakya/models/base.py`
- Create: `src/vaakya/models/__init__.py`
- Create: `src/vaakya/models/user.py`
- Create: `src/vaakya/models/meeting.py`
- Create: `src/vaakya/models/note.py`
- Create: `src/vaakya/models/share.py`
- Create: `alembic.ini`
- Create: `alembic/env.py`

- [ ] **Step 1: Initialize Alembic**

```bash
uv run alembic init alembic
```

- [ ] **Step 2: Create base model**

Write `src/vaakya/models/base.py`:
```python
import uuid
from datetime import datetime

from sqlalchemy import DateTime, func
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column


class Base(DeclarativeBase):
    pass


class TimestampMixin:
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


def new_uuid() -> str:
    return str(uuid.uuid4())
```

- [ ] **Step 3: Create User model**

Write `src/vaakya/models/user.py`:
```python
from sqlalchemy import String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from vaakya.models.base import Base, TimestampMixin, new_uuid


class User(TimestampMixin, Base):
    __tablename__ = "users"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    email: Mapped[str] = mapped_column(String(255), unique=True, index=True)
    name: Mapped[str] = mapped_column(String(255))
    provider: Mapped[str] = mapped_column(String(50))  # "apple" or "google"
    provider_id: Mapped[str] = mapped_column(String(255))
    avatar_url: Mapped[str | None] = mapped_column(String(500), nullable=True)

    meetings = relationship("Meeting", back_populates="user")
```

- [ ] **Step 4: Create Meeting model**

Write `src/vaakya/models/meeting.py`:
```python
from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from vaakya.models.base import Base, TimestampMixin, new_uuid


class Meeting(TimestampMixin, Base):
    __tablename__ = "meetings"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), index=True)
    title: Mapped[str] = mapped_column(String(500))
    started_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    ended_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    duration_seconds: Mapped[int | None] = mapped_column(Integer, nullable=True)
    speaker_count: Mapped[int] = mapped_column(Integer, default=0)
    transcript: Mapped[str | None] = mapped_column(Text, nullable=True)
    audio_url: Mapped[str | None] = mapped_column(String(500), nullable=True)
    template: Mapped[str | None] = mapped_column(String(50), nullable=True)
    ai_provider: Mapped[str | None] = mapped_column(String(50), nullable=True)

    user = relationship("User", back_populates="meetings")
    blocks = relationship(
        "Block", back_populates="meeting", cascade="all, delete-orphan"
    )
```

- [ ] **Step 5: Create Note/Block model**

Write `src/vaakya/models/note.py`:
```python
from sqlalchemy import ForeignKey, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from vaakya.models.base import Base, TimestampMixin, new_uuid


class Block(TimestampMixin, Base):
    __tablename__ = "blocks"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    meeting_id: Mapped[str] = mapped_column(ForeignKey("meetings.id"), index=True)
    type: Mapped[str] = mapped_column(String(50))  # summary, decision, action, quote
    content: Mapped[str] = mapped_column(Text)
    speaker: Mapped[str | None] = mapped_column(String(255), nullable=True)
    timestamp_seconds: Mapped[int | None] = mapped_column(Integer, nullable=True)
    position: Mapped[int] = mapped_column(Integer, default=0)
    is_checked: Mapped[bool] = mapped_column(default=False)
    is_ai_generated: Mapped[bool] = mapped_column(default=True)
    meta_text: Mapped[str | None] = mapped_column(String(500), nullable=True)

    meeting = relationship("Meeting", back_populates="blocks")
```

- [ ] **Step 6: Create ShareLink model**

Write `src/vaakya/models/share.py`:
```python
from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, String
from sqlalchemy.orm import Mapped, mapped_column

from vaakya.models.base import Base, TimestampMixin, new_uuid


class ShareLink(TimestampMixin, Base):
    __tablename__ = "share_links"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    meeting_id: Mapped[str] = mapped_column(ForeignKey("meetings.id"), index=True)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"))
    token: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    expires_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
```

- [ ] **Step 7: Create models __init__**

Write `src/vaakya/models/__init__.py`:
```python
from vaakya.models.base import Base
from vaakya.models.meeting import Meeting
from vaakya.models.note import Block
from vaakya.models.share import ShareLink
from vaakya.models.user import User

__all__ = ["Base", "User", "Meeting", "Block", "ShareLink"]
```

- [ ] **Step 8: Configure Alembic**

Replace `alembic/env.py` with:
```python
import asyncio
from logging.config import fileConfig

from alembic import context
from sqlalchemy.ext.asyncio import create_async_engine

from vaakya.config import settings
from vaakya.models import Base

config = context.config
if config.config_file_name is not None:
    fileConfig(config.config_file_name)

target_metadata = Base.metadata


def run_migrations_offline():
    context.configure(url=settings.database_url, target_metadata=target_metadata)
    with context.begin_transaction():
        context.run_migrations()


def do_run_migrations(connection):
    context.configure(connection=connection, target_metadata=target_metadata)
    with context.begin_transaction():
        context.run_migrations()


async def run_migrations_online():
    engine = create_async_engine(settings.database_url)
    async with engine.connect() as connection:
        await connection.run_sync(do_run_migrations)
    await engine.dispose()


if context.is_offline_mode():
    run_migrations_offline()
else:
    asyncio.run(run_migrations_online())
```

Update `alembic.ini` — set `sqlalchemy.url` to empty (we use config.py):
```bash
sed -i '' 's|sqlalchemy.url = .*|sqlalchemy.url = |' alembic.ini
```

- [ ] **Step 9: Generate and run migration**

```bash
make up
uv run alembic revision --autogenerate -m "initial tables"
uv run alembic upgrade head
```

- [ ] **Step 10: Verify tables exist**

```bash
docker exec -it meeting_genie-postgres-1 psql -U vaakya -c "\dt"
```

Expected: `users`, `meetings`, `blocks`, `share_links` tables listed.

- [ ] **Step 11: Commit**

```bash
git add -A
git commit -m "feat: database models and initial migration"
```

---

### Task 3: Auth — JWT + Dependency Injection

**Files:**
- Create: `src/vaakya/schemas/auth.py`
- Create: `src/vaakya/deps.py`
- Create: `src/vaakya/routers/auth.py`
- Create: `src/vaakya/schemas/__init__.py`
- Create: `src/vaakya/routers/__init__.py`
- Modify: `src/vaakya/main.py` (mount router)
- Create: `tests/conftest.py`
- Create: `tests/test_auth.py`

- [ ] **Step 1: Create auth schemas**

Write `src/vaakya/schemas/__init__.py`:
```python
```

Write `src/vaakya/schemas/auth.py`:
```python
from pydantic import BaseModel, EmailStr


class LoginRequest(BaseModel):
    email: EmailStr
    name: str
    provider: str  # "apple" or "google"
    provider_id: str
    avatar_url: str | None = None


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"


class UserResponse(BaseModel):
    id: str
    email: str
    name: str
    provider: str
    avatar_url: str | None

    model_config = {"from_attributes": True}
```

- [ ] **Step 2: Create deps.py**

Write `src/vaakya/deps.py`:
```python
from typing import Annotated

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jose import JWTError, jwt
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from vaakya.config import settings
from vaakya.db import async_session
from vaakya.models.user import User

security = HTTPBearer()


async def get_db():
    async with async_session() as session:
        yield session


async def get_current_user(
    creds: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> User:
    try:
        payload = jwt.decode(
            creds.credentials, settings.jwt_secret, algorithms=[settings.jwt_algorithm]
        )
        user_id: str = payload.get("sub")
        if user_id is None:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED)
    except JWTError:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED)

    result = await db.execute(select(User).where(User.id == user_id))
    user = result.scalar_one_or_none()
    if user is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED)
    return user


DB = Annotated[AsyncSession, Depends(get_db)]
CurrentUser = Annotated[User, Depends(get_current_user)]
```

- [ ] **Step 3: Create auth router**

Write `src/vaakya/routers/__init__.py`:
```python
```

Write `src/vaakya/routers/auth.py`:
```python
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter
from jose import jwt
from sqlalchemy import select

from vaakya.config import settings
from vaakya.deps import DB
from vaakya.models.user import User
from vaakya.schemas.auth import LoginRequest, TokenResponse, UserResponse

router = APIRouter(prefix="/auth", tags=["auth"])


def create_token(user_id: str) -> str:
    expire = datetime.now(timezone.utc) + timedelta(
        minutes=settings.jwt_expire_minutes
    )
    return jwt.encode(
        {"sub": user_id, "exp": expire},
        settings.jwt_secret,
        algorithm=settings.jwt_algorithm,
    )


@router.post("/login", response_model=TokenResponse)
async def login(body: LoginRequest, db: DB):
    result = await db.execute(select(User).where(User.email == body.email))
    user = result.scalar_one_or_none()

    if user is None:
        user = User(
            email=body.email,
            name=body.name,
            provider=body.provider,
            provider_id=body.provider_id,
            avatar_url=body.avatar_url,
        )
        db.add(user)
        await db.commit()
        await db.refresh(user)

    return TokenResponse(access_token=create_token(user.id))


@router.get("/me", response_model=UserResponse)
async def me(user: "CurrentUser"):
    return user
```

Fix the circular import — use string annotation for `CurrentUser`:
```python
# At the top of auth.py, add:
from vaakya.deps import DB, CurrentUser
# Remove the string annotation, use directly:
```

Actually, let me write it cleanly:

Replace `src/vaakya/routers/auth.py`:
```python
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter
from jose import jwt
from sqlalchemy import select

from vaakya.config import settings
from vaakya.deps import DB, CurrentUser
from vaakya.models.user import User
from vaakya.schemas.auth import LoginRequest, TokenResponse, UserResponse

router = APIRouter(prefix="/auth", tags=["auth"])


def create_token(user_id: str) -> str:
    expire = datetime.now(timezone.utc) + timedelta(
        minutes=settings.jwt_expire_minutes
    )
    return jwt.encode(
        {"sub": user_id, "exp": expire},
        settings.jwt_secret,
        algorithm=settings.jwt_algorithm,
    )


@router.post("/login", response_model=TokenResponse)
async def login(body: LoginRequest, db: DB):
    result = await db.execute(select(User).where(User.email == body.email))
    user = result.scalar_one_or_none()

    if user is None:
        user = User(
            email=body.email,
            name=body.name,
            provider=body.provider,
            provider_id=body.provider_id,
            avatar_url=body.avatar_url,
        )
        db.add(user)
        await db.commit()
        await db.refresh(user)

    return TokenResponse(access_token=create_token(user.id))


@router.get("/me", response_model=UserResponse)
async def me(user: CurrentUser):
    return user
```

- [ ] **Step 4: Mount router in main.py**

Replace `src/vaakya/main.py`:
```python
from contextlib import asynccontextmanager

from fastapi import FastAPI

from vaakya.config import settings
from vaakya.db import engine
from vaakya.routers import auth


@asynccontextmanager
async def lifespan(app: FastAPI):
    yield
    await engine.dispose()


app = FastAPI(
    title="Vaakya API",
    version="0.1.0",
    lifespan=lifespan,
)

app.include_router(auth.router)


@app.get("/health")
async def health():
    return {"status": "ok", "env": settings.vaakya_env}
```

- [ ] **Step 5: Write test fixtures**

Write `tests/conftest.py`:
```python
import asyncio
from collections.abc import AsyncGenerator

import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from vaakya.config import settings
from vaakya.deps import get_db
from vaakya.main import app
from vaakya.models.base import Base

TEST_DB_URL = settings.database_url.replace("/vaakya", "/vaakya_test")

engine_test = create_async_engine(TEST_DB_URL)
session_test = async_sessionmaker(engine_test, expire_on_commit=False)


@pytest.fixture(scope="session")
def event_loop():
    loop = asyncio.new_event_loop()
    yield loop
    loop.close()


@pytest.fixture(autouse=True)
async def setup_db():
    async with engine_test.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    yield
    async with engine_test.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)


async def override_get_db() -> AsyncGenerator[AsyncSession, None]:
    async with session_test() as session:
        yield session


app.dependency_overrides[get_db] = override_get_db


@pytest.fixture
async def client():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as c:
        yield c


@pytest.fixture
async def auth_headers(client: AsyncClient) -> dict:
    resp = await client.post(
        "/auth/login",
        json={
            "email": "test@vaakya.ai",
            "name": "Test User",
            "provider": "google",
            "provider_id": "google-123",
        },
    )
    token = resp.json()["access_token"]
    return {"Authorization": f"Bearer {token}"}
```

- [ ] **Step 6: Write auth tests**

Write `tests/test_auth.py`:
```python
import pytest
from httpx import AsyncClient


@pytest.mark.asyncio
async def test_login_creates_user(client: AsyncClient):
    resp = await client.post(
        "/auth/login",
        json={
            "email": "new@vaakya.ai",
            "name": "New User",
            "provider": "google",
            "provider_id": "g-456",
        },
    )
    assert resp.status_code == 200
    data = resp.json()
    assert "access_token" in data
    assert data["token_type"] == "bearer"


@pytest.mark.asyncio
async def test_login_returns_same_token_for_existing(client: AsyncClient):
    payload = {
        "email": "repeat@vaakya.ai",
        "name": "Repeat",
        "provider": "apple",
        "provider_id": "a-789",
    }
    resp1 = await client.post("/auth/login", json=payload)
    resp2 = await client.post("/auth/login", json=payload)
    assert resp1.status_code == 200
    assert resp2.status_code == 200


@pytest.mark.asyncio
async def test_me_returns_user(client: AsyncClient, auth_headers: dict):
    resp = await client.get("/auth/me", headers=auth_headers)
    assert resp.status_code == 200
    data = resp.json()
    assert data["email"] == "test@vaakya.ai"
    assert data["name"] == "Test User"


@pytest.mark.asyncio
async def test_me_rejects_bad_token(client: AsyncClient):
    resp = await client.get(
        "/auth/me", headers={"Authorization": "Bearer bad-token"}
    )
    assert resp.status_code == 401
```

- [ ] **Step 7: Create test database and run tests**

```bash
docker exec -it meeting_genie-postgres-1 psql -U vaakya -c "CREATE DATABASE vaakya_test;"
uv run pytest tests/test_auth.py -v
```

Expected: 4 tests pass.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat: auth with JWT login, /me endpoint, test suite"
```

---

### Task 4: Meetings CRUD

**Files:**
- Create: `src/vaakya/schemas/meeting.py`
- Create: `src/vaakya/routers/meetings.py`
- Modify: `src/vaakya/main.py` (mount router)
- Create: `tests/test_meetings.py`

- [ ] **Step 1: Create meeting schemas**

Write `src/vaakya/schemas/meeting.py`:
```python
from datetime import datetime

from pydantic import BaseModel


class MeetingCreate(BaseModel):
    title: str
    started_at: datetime
    ended_at: datetime | None = None
    duration_seconds: int | None = None
    speaker_count: int = 0
    transcript: str | None = None
    template: str | None = None
    ai_provider: str | None = None


class MeetingUpdate(BaseModel):
    title: str | None = None
    ended_at: datetime | None = None
    duration_seconds: int | None = None
    speaker_count: int | None = None
    transcript: str | None = None
    template: str | None = None
    ai_provider: str | None = None


class MeetingResponse(BaseModel):
    id: str
    user_id: str
    title: str
    started_at: datetime
    ended_at: datetime | None
    duration_seconds: int | None
    speaker_count: int
    template: str | None
    ai_provider: str | None
    created_at: datetime

    model_config = {"from_attributes": True}
```

- [ ] **Step 2: Create meetings router**

Write `src/vaakya/routers/meetings.py`:
```python
from fastapi import APIRouter, HTTPException, status
from sqlalchemy import select

from vaakya.deps import DB, CurrentUser
from vaakya.models.meeting import Meeting
from vaakya.schemas.meeting import MeetingCreate, MeetingResponse, MeetingUpdate

router = APIRouter(prefix="/meetings", tags=["meetings"])


@router.post("", response_model=MeetingResponse, status_code=201)
async def create_meeting(body: MeetingCreate, db: DB, user: CurrentUser):
    meeting = Meeting(**body.model_dump(), user_id=user.id)
    db.add(meeting)
    await db.commit()
    await db.refresh(meeting)
    return meeting


@router.get("", response_model=list[MeetingResponse])
async def list_meetings(db: DB, user: CurrentUser):
    result = await db.execute(
        select(Meeting)
        .where(Meeting.user_id == user.id)
        .order_by(Meeting.started_at.desc())
    )
    return result.scalars().all()


@router.get("/{meeting_id}", response_model=MeetingResponse)
async def get_meeting(meeting_id: str, db: DB, user: CurrentUser):
    result = await db.execute(
        select(Meeting).where(Meeting.id == meeting_id, Meeting.user_id == user.id)
    )
    meeting = result.scalar_one_or_none()
    if meeting is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND)
    return meeting


@router.patch("/{meeting_id}", response_model=MeetingResponse)
async def update_meeting(
    meeting_id: str, body: MeetingUpdate, db: DB, user: CurrentUser
):
    result = await db.execute(
        select(Meeting).where(Meeting.id == meeting_id, Meeting.user_id == user.id)
    )
    meeting = result.scalar_one_or_none()
    if meeting is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND)

    for key, value in body.model_dump(exclude_unset=True).items():
        setattr(meeting, key, value)

    await db.commit()
    await db.refresh(meeting)
    return meeting


@router.delete("/{meeting_id}", status_code=204)
async def delete_meeting(meeting_id: str, db: DB, user: CurrentUser):
    result = await db.execute(
        select(Meeting).where(Meeting.id == meeting_id, Meeting.user_id == user.id)
    )
    meeting = result.scalar_one_or_none()
    if meeting is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND)

    await db.delete(meeting)
    await db.commit()
```

- [ ] **Step 3: Mount in main.py**

Add to `src/vaakya/main.py` after `auth` import:
```python
from vaakya.routers import auth, meetings
```
And after `app.include_router(auth.router)`:
```python
app.include_router(meetings.router)
```

- [ ] **Step 4: Write meeting tests**

Write `tests/test_meetings.py`:
```python
import pytest
from httpx import AsyncClient


@pytest.mark.asyncio
async def test_create_meeting(client: AsyncClient, auth_headers: dict):
    resp = await client.post(
        "/meetings",
        json={
            "title": "Weekly Standup",
            "started_at": "2026-03-31T15:30:00Z",
            "speaker_count": 4,
        },
        headers=auth_headers,
    )
    assert resp.status_code == 201
    data = resp.json()
    assert data["title"] == "Weekly Standup"
    assert data["speaker_count"] == 4


@pytest.mark.asyncio
async def test_list_meetings(client: AsyncClient, auth_headers: dict):
    await client.post(
        "/meetings",
        json={"title": "Meeting 1", "started_at": "2026-03-31T10:00:00Z"},
        headers=auth_headers,
    )
    await client.post(
        "/meetings",
        json={"title": "Meeting 2", "started_at": "2026-03-31T14:00:00Z"},
        headers=auth_headers,
    )
    resp = await client.get("/meetings", headers=auth_headers)
    assert resp.status_code == 200
    data = resp.json()
    assert len(data) >= 2


@pytest.mark.asyncio
async def test_get_meeting(client: AsyncClient, auth_headers: dict):
    create = await client.post(
        "/meetings",
        json={"title": "Get Me", "started_at": "2026-03-31T10:00:00Z"},
        headers=auth_headers,
    )
    mid = create.json()["id"]
    resp = await client.get(f"/meetings/{mid}", headers=auth_headers)
    assert resp.status_code == 200
    assert resp.json()["title"] == "Get Me"


@pytest.mark.asyncio
async def test_update_meeting(client: AsyncClient, auth_headers: dict):
    create = await client.post(
        "/meetings",
        json={"title": "Old Title", "started_at": "2026-03-31T10:00:00Z"},
        headers=auth_headers,
    )
    mid = create.json()["id"]
    resp = await client.patch(
        f"/meetings/{mid}",
        json={"title": "New Title", "duration_seconds": 1680},
        headers=auth_headers,
    )
    assert resp.status_code == 200
    assert resp.json()["title"] == "New Title"
    assert resp.json()["duration_seconds"] == 1680


@pytest.mark.asyncio
async def test_delete_meeting(client: AsyncClient, auth_headers: dict):
    create = await client.post(
        "/meetings",
        json={"title": "Delete Me", "started_at": "2026-03-31T10:00:00Z"},
        headers=auth_headers,
    )
    mid = create.json()["id"]
    resp = await client.delete(f"/meetings/{mid}", headers=auth_headers)
    assert resp.status_code == 204

    resp = await client.get(f"/meetings/{mid}", headers=auth_headers)
    assert resp.status_code == 404


@pytest.mark.asyncio
async def test_meeting_not_found(client: AsyncClient, auth_headers: dict):
    resp = await client.get("/meetings/nonexistent", headers=auth_headers)
    assert resp.status_code == 404
```

- [ ] **Step 5: Run tests**

```bash
uv run pytest tests/test_meetings.py -v
```

Expected: 6 tests pass.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: meetings CRUD with tests"
```

---

### Task 5: Blocks (Notes) CRUD

**Files:**
- Create: `src/vaakya/schemas/note.py`
- Create: `src/vaakya/routers/notes.py`
- Modify: `src/vaakya/main.py` (mount router)
- Create: `tests/test_notes.py`

- [ ] **Step 1: Create block schemas**

Write `src/vaakya/schemas/note.py`:
```python
from pydantic import BaseModel


class BlockCreate(BaseModel):
    type: str  # summary, decision, action, quote, heading, text
    content: str
    speaker: str | None = None
    timestamp_seconds: int | None = None
    position: int = 0
    is_ai_generated: bool = True
    meta_text: str | None = None


class BlockUpdate(BaseModel):
    content: str | None = None
    position: int | None = None
    is_checked: bool | None = None
    speaker: str | None = None
    meta_text: str | None = None


class BlockResponse(BaseModel):
    id: str
    meeting_id: str
    type: str
    content: str
    speaker: str | None
    timestamp_seconds: int | None
    position: int
    is_checked: bool
    is_ai_generated: bool
    meta_text: str | None

    model_config = {"from_attributes": True}
```

- [ ] **Step 2: Create notes router**

Write `src/vaakya/routers/notes.py`:
```python
from fastapi import APIRouter, HTTPException, status
from sqlalchemy import select

from vaakya.deps import DB, CurrentUser
from vaakya.models.meeting import Meeting
from vaakya.models.note import Block
from vaakya.schemas.note import BlockCreate, BlockResponse, BlockUpdate

router = APIRouter(prefix="/meetings/{meeting_id}/blocks", tags=["blocks"])


async def _get_meeting(meeting_id: str, user_id: str, db) -> Meeting:
    result = await db.execute(
        select(Meeting).where(Meeting.id == meeting_id, Meeting.user_id == user_id)
    )
    meeting = result.scalar_one_or_none()
    if meeting is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND)
    return meeting


@router.post("", response_model=BlockResponse, status_code=201)
async def create_block(
    meeting_id: str, body: BlockCreate, db: DB, user: CurrentUser
):
    await _get_meeting(meeting_id, user.id, db)
    block = Block(**body.model_dump(), meeting_id=meeting_id)
    db.add(block)
    await db.commit()
    await db.refresh(block)
    return block


@router.get("", response_model=list[BlockResponse])
async def list_blocks(meeting_id: str, db: DB, user: CurrentUser):
    await _get_meeting(meeting_id, user.id, db)
    result = await db.execute(
        select(Block)
        .where(Block.meeting_id == meeting_id)
        .order_by(Block.position)
    )
    return result.scalars().all()


@router.patch("/{block_id}", response_model=BlockResponse)
async def update_block(
    meeting_id: str, block_id: str, body: BlockUpdate, db: DB, user: CurrentUser
):
    await _get_meeting(meeting_id, user.id, db)
    result = await db.execute(
        select(Block).where(Block.id == block_id, Block.meeting_id == meeting_id)
    )
    block = result.scalar_one_or_none()
    if block is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND)

    for key, value in body.model_dump(exclude_unset=True).items():
        setattr(block, key, value)

    await db.commit()
    await db.refresh(block)
    return block


@router.delete("/{block_id}", status_code=204)
async def delete_block(
    meeting_id: str, block_id: str, db: DB, user: CurrentUser
):
    await _get_meeting(meeting_id, user.id, db)
    result = await db.execute(
        select(Block).where(Block.id == block_id, Block.meeting_id == meeting_id)
    )
    block = result.scalar_one_or_none()
    if block is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND)

    await db.delete(block)
    await db.commit()
```

- [ ] **Step 3: Mount in main.py**

Update imports in `src/vaakya/main.py`:
```python
from vaakya.routers import auth, meetings, notes
```
Add:
```python
app.include_router(notes.router)
```

- [ ] **Step 4: Write block tests**

Write `tests/test_notes.py`:
```python
import pytest
from httpx import AsyncClient


async def _create_meeting(client: AsyncClient, headers: dict) -> str:
    resp = await client.post(
        "/meetings",
        json={"title": "Test Meeting", "started_at": "2026-03-31T15:00:00Z"},
        headers=headers,
    )
    return resp.json()["id"]


@pytest.mark.asyncio
async def test_create_block(client: AsyncClient, auth_headers: dict):
    mid = await _create_meeting(client, auth_headers)
    resp = await client.post(
        f"/meetings/{mid}/blocks",
        json={"type": "summary", "content": "Team discussed releases.", "position": 0},
        headers=auth_headers,
    )
    assert resp.status_code == 201
    data = resp.json()
    assert data["type"] == "summary"
    assert data["content"] == "Team discussed releases."


@pytest.mark.asyncio
async def test_list_blocks_ordered(client: AsyncClient, auth_headers: dict):
    mid = await _create_meeting(client, auth_headers)
    await client.post(
        f"/meetings/{mid}/blocks",
        json={"type": "decision", "content": "Weekly releases", "position": 1},
        headers=auth_headers,
    )
    await client.post(
        f"/meetings/{mid}/blocks",
        json={"type": "summary", "content": "Overview", "position": 0},
        headers=auth_headers,
    )
    resp = await client.get(f"/meetings/{mid}/blocks", headers=auth_headers)
    assert resp.status_code == 200
    data = resp.json()
    assert len(data) == 2
    assert data[0]["position"] == 0
    assert data[1]["position"] == 1


@pytest.mark.asyncio
async def test_update_block_check(client: AsyncClient, auth_headers: dict):
    mid = await _create_meeting(client, auth_headers)
    create = await client.post(
        f"/meetings/{mid}/blocks",
        json={"type": "action", "content": "Update CI", "position": 0},
        headers=auth_headers,
    )
    bid = create.json()["id"]
    resp = await client.patch(
        f"/meetings/{mid}/blocks/{bid}",
        json={"is_checked": True},
        headers=auth_headers,
    )
    assert resp.status_code == 200
    assert resp.json()["is_checked"] is True


@pytest.mark.asyncio
async def test_delete_block(client: AsyncClient, auth_headers: dict):
    mid = await _create_meeting(client, auth_headers)
    create = await client.post(
        f"/meetings/{mid}/blocks",
        json={"type": "quote", "content": "Ship faster", "position": 0},
        headers=auth_headers,
    )
    bid = create.json()["id"]
    resp = await client.delete(
        f"/meetings/{mid}/blocks/{bid}", headers=auth_headers
    )
    assert resp.status_code == 204
```

- [ ] **Step 5: Run tests**

```bash
uv run pytest tests/test_notes.py -v
```

Expected: 4 tests pass.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: blocks CRUD for meeting notes"
```

---

### Task 6: AI Enhancement Endpoint

**Files:**
- Create: `src/vaakya/services/__init__.py`
- Create: `src/vaakya/services/ai.py`
- Create: `src/vaakya/routers/enhance.py`
- Modify: `src/vaakya/main.py` (mount router)
- Create: `tests/test_enhance.py`

- [ ] **Step 1: Create AI service**

Write `src/vaakya/services/__init__.py`:
```python
```

Write `src/vaakya/services/ai.py`:
```python
import httpx

from vaakya.config import settings

ENHANCE_PROMPT = """You are a meeting notes assistant. Given a transcript and optional user notes, produce structured meeting notes as JSON.

Return a JSON array of blocks, each with:
- "type": one of "summary", "decision", "action", "quote"
- "content": the text
- "speaker": who said it (null for summary)
- "timestamp_seconds": seconds into the meeting (null if unknown)
- "meta_text": additional context like "Proposed by X" or "Due Friday"

Transcript:
{transcript}

User Notes:
{user_notes}

Template: {template}

Return ONLY valid JSON array. No markdown fencing."""


async def enhance_meeting(
    transcript: str,
    user_notes: str = "",
    template: str = "general",
    provider: str | None = None,
    api_key: str | None = None,
) -> list[dict]:
    active_provider = provider or settings.ai_provider

    if active_provider == "ollama":
        return await _enhance_ollama(transcript, user_notes, template)
    elif active_provider == "openai":
        return await _enhance_openai(transcript, user_notes, template, api_key)
    elif active_provider == "anthropic":
        return await _enhance_anthropic(transcript, user_notes, template, api_key)
    else:
        return await _enhance_ollama(transcript, user_notes, template)


async def _enhance_ollama(
    transcript: str, user_notes: str, template: str
) -> list[dict]:
    prompt = ENHANCE_PROMPT.format(
        transcript=transcript, user_notes=user_notes, template=template
    )
    async with httpx.AsyncClient(timeout=120) as client:
        resp = await client.post(
            f"{settings.ollama_base_url}/api/generate",
            json={"model": "llama3.2", "prompt": prompt, "stream": False},
        )
        resp.raise_for_status()
        import json

        text = resp.json()["response"]
        return json.loads(text)


async def _enhance_openai(
    transcript: str, user_notes: str, template: str, api_key: str | None
) -> list[dict]:
    prompt = ENHANCE_PROMPT.format(
        transcript=transcript, user_notes=user_notes, template=template
    )
    async with httpx.AsyncClient(timeout=120) as client:
        resp = await client.post(
            "https://api.openai.com/v1/chat/completions",
            headers={"Authorization": f"Bearer {api_key}"},
            json={
                "model": "gpt-4o",
                "messages": [{"role": "user", "content": prompt}],
                "response_format": {"type": "json_object"},
            },
        )
        resp.raise_for_status()
        import json

        content = resp.json()["choices"][0]["message"]["content"]
        parsed = json.loads(content)
        return parsed if isinstance(parsed, list) else parsed.get("blocks", [])


async def _enhance_anthropic(
    transcript: str, user_notes: str, template: str, api_key: str | None
) -> list[dict]:
    prompt = ENHANCE_PROMPT.format(
        transcript=transcript, user_notes=user_notes, template=template
    )
    async with httpx.AsyncClient(timeout=120) as client:
        resp = await client.post(
            "https://api.anthropic.com/v1/messages",
            headers={
                "x-api-key": api_key,
                "anthropic-version": "2023-06-01",
                "content-type": "application/json",
            },
            json={
                "model": "claude-sonnet-4-6-20250514",
                "max_tokens": 4096,
                "messages": [{"role": "user", "content": prompt}],
            },
        )
        resp.raise_for_status()
        import json

        text = resp.json()["content"][0]["text"]
        return json.loads(text)
```

- [ ] **Step 2: Create enhance router**

Write `src/vaakya/routers/enhance.py`:
```python
from fastapi import APIRouter, HTTPException, status
from pydantic import BaseModel
from sqlalchemy import select

from vaakya.deps import DB, CurrentUser
from vaakya.models.meeting import Meeting
from vaakya.models.note import Block
from vaakya.schemas.note import BlockResponse
from vaakya.services.ai import enhance_meeting

router = APIRouter(tags=["enhance"])


class EnhanceRequest(BaseModel):
    template: str = "general"
    user_notes: str = ""
    provider: str | None = None
    api_key: str | None = None


@router.post(
    "/meetings/{meeting_id}/enhance", response_model=list[BlockResponse]
)
async def enhance(
    meeting_id: str, body: EnhanceRequest, db: DB, user: CurrentUser
):
    result = await db.execute(
        select(Meeting).where(Meeting.id == meeting_id, Meeting.user_id == user.id)
    )
    meeting = result.scalar_one_or_none()
    if meeting is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND)

    if not meeting.transcript:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Meeting has no transcript",
        )

    ai_blocks = await enhance_meeting(
        transcript=meeting.transcript,
        user_notes=body.user_notes,
        template=body.template,
        provider=body.provider,
        api_key=body.api_key,
    )

    # Clear existing AI blocks
    existing = await db.execute(
        select(Block).where(
            Block.meeting_id == meeting_id, Block.is_ai_generated == True  # noqa: E712
        )
    )
    for block in existing.scalars():
        await db.delete(block)

    # Create new blocks
    created = []
    for i, b in enumerate(ai_blocks):
        block = Block(
            meeting_id=meeting_id,
            type=b.get("type", "text"),
            content=b.get("content", ""),
            speaker=b.get("speaker"),
            timestamp_seconds=b.get("timestamp_seconds"),
            position=i,
            is_ai_generated=True,
            meta_text=b.get("meta_text"),
        )
        db.add(block)
        created.append(block)

    meeting.template = body.template
    meeting.ai_provider = body.provider or "platform"
    await db.commit()

    for block in created:
        await db.refresh(block)
    return created
```

- [ ] **Step 3: Mount in main.py**

Update imports:
```python
from vaakya.routers import auth, meetings, notes, enhance
```
Add:
```python
app.include_router(enhance.router)
```

- [ ] **Step 4: Write enhance tests (mocked)**

Write `tests/test_enhance.py`:
```python
from unittest.mock import AsyncMock, patch

import pytest
from httpx import AsyncClient


async def _create_meeting_with_transcript(
    client: AsyncClient, headers: dict
) -> str:
    resp = await client.post(
        "/meetings",
        json={
            "title": "Standup",
            "started_at": "2026-03-31T15:30:00Z",
            "speaker_count": 4,
        },
        headers=headers,
    )
    mid = resp.json()["id"]
    await client.patch(
        f"/meetings/{mid}",
        json={"transcript": "Priya: We need to ship faster. Ravi: I can update CI by Friday."},
        headers=headers,
    )
    return mid


MOCK_AI_RESPONSE = [
    {"type": "summary", "content": "Team discussed releases.", "speaker": None, "timestamp_seconds": None, "meta_text": None},
    {"type": "action", "content": "Update CI pipeline", "speaker": "Ravi", "timestamp_seconds": 98, "meta_text": "Due Friday"},
]


@pytest.mark.asyncio
@patch("vaakya.routers.enhance.enhance_meeting", new_callable=AsyncMock)
async def test_enhance_meeting(
    mock_ai, client: AsyncClient, auth_headers: dict
):
    mock_ai.return_value = MOCK_AI_RESPONSE
    mid = await _create_meeting_with_transcript(client, auth_headers)

    resp = await client.post(
        f"/meetings/{mid}/enhance",
        json={"template": "standup"},
        headers=auth_headers,
    )
    assert resp.status_code == 200
    data = resp.json()
    assert len(data) == 2
    assert data[0]["type"] == "summary"
    assert data[1]["type"] == "action"
    assert data[1]["speaker"] == "Ravi"


@pytest.mark.asyncio
async def test_enhance_no_transcript(client: AsyncClient, auth_headers: dict):
    resp = await client.post(
        "/meetings",
        json={"title": "Empty", "started_at": "2026-03-31T15:30:00Z"},
        headers=auth_headers,
    )
    mid = resp.json()["id"]
    resp = await client.post(
        f"/meetings/{mid}/enhance",
        json={},
        headers=auth_headers,
    )
    assert resp.status_code == 400
    assert "transcript" in resp.json()["detail"].lower()
```

- [ ] **Step 5: Run tests**

```bash
uv run pytest tests/test_enhance.py -v
```

Expected: 2 tests pass.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: AI enhancement endpoint with provider routing"
```

---

### Task 7: Share Links

**Files:**
- Create: `src/vaakya/schemas/share.py`
- Create: `src/vaakya/routers/share.py`
- Modify: `src/vaakya/main.py` (mount router)
- Create: `tests/test_share.py`

- [ ] **Step 1: Create share schemas**

Write `src/vaakya/schemas/share.py`:
```python
from datetime import datetime

from pydantic import BaseModel

from vaakya.schemas.meeting import MeetingResponse
from vaakya.schemas.note import BlockResponse


class ShareCreate(BaseModel):
    expires_in_hours: int | None = None


class ShareResponse(BaseModel):
    token: str
    url: str
    expires_at: datetime | None

    model_config = {"from_attributes": True}


class SharedNoteView(BaseModel):
    meeting: MeetingResponse
    blocks: list[BlockResponse]
```

- [ ] **Step 2: Create share router**

Write `src/vaakya/routers/share.py`:
```python
import secrets
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, HTTPException, status
from sqlalchemy import select

from vaakya.deps import DB, CurrentUser
from vaakya.models.meeting import Meeting
from vaakya.models.note import Block
from vaakya.models.share import ShareLink
from vaakya.schemas.share import ShareCreate, SharedNoteView, ShareResponse

router = APIRouter(tags=["share"])


@router.post("/meetings/{meeting_id}/share", response_model=ShareResponse)
async def create_share(
    meeting_id: str, body: ShareCreate, db: DB, user: CurrentUser
):
    result = await db.execute(
        select(Meeting).where(Meeting.id == meeting_id, Meeting.user_id == user.id)
    )
    if result.scalar_one_or_none() is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND)

    token = secrets.token_urlsafe(32)
    expires_at = None
    if body.expires_in_hours:
        expires_at = datetime.now(timezone.utc) + timedelta(hours=body.expires_in_hours)

    link = ShareLink(
        meeting_id=meeting_id,
        user_id=user.id,
        token=token,
        expires_at=expires_at,
    )
    db.add(link)
    await db.commit()
    await db.refresh(link)

    return ShareResponse(
        token=link.token,
        url=f"/share/{link.token}",
        expires_at=link.expires_at,
    )


@router.get("/share/{token}", response_model=SharedNoteView)
async def view_shared(token: str, db: DB):
    result = await db.execute(
        select(ShareLink).where(ShareLink.token == token)
    )
    link = result.scalar_one_or_none()
    if link is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND)

    if link.expires_at and link.expires_at < datetime.now(timezone.utc):
        raise HTTPException(
            status_code=status.HTTP_410_GONE, detail="Link expired"
        )

    meeting_result = await db.execute(
        select(Meeting).where(Meeting.id == link.meeting_id)
    )
    meeting = meeting_result.scalar_one()

    blocks_result = await db.execute(
        select(Block)
        .where(Block.meeting_id == link.meeting_id)
        .order_by(Block.position)
    )
    blocks = blocks_result.scalars().all()

    return SharedNoteView(meeting=meeting, blocks=blocks)
```

- [ ] **Step 3: Mount in main.py**

Update imports:
```python
from vaakya.routers import auth, enhance, meetings, notes, share
```
Add:
```python
app.include_router(share.router)
```

- [ ] **Step 4: Write share tests**

Write `tests/test_share.py`:
```python
import pytest
from httpx import AsyncClient


async def _create_meeting_with_blocks(
    client: AsyncClient, headers: dict
) -> str:
    resp = await client.post(
        "/meetings",
        json={"title": "Shareable", "started_at": "2026-03-31T15:30:00Z"},
        headers=headers,
    )
    mid = resp.json()["id"]
    await client.post(
        f"/meetings/{mid}/blocks",
        json={"type": "summary", "content": "Discussion about releases.", "position": 0},
        headers=headers,
    )
    return mid


@pytest.mark.asyncio
async def test_create_share_link(client: AsyncClient, auth_headers: dict):
    mid = await _create_meeting_with_blocks(client, auth_headers)
    resp = await client.post(
        f"/meetings/{mid}/share", json={}, headers=auth_headers
    )
    assert resp.status_code == 200
    data = resp.json()
    assert "token" in data
    assert data["url"].startswith("/share/")


@pytest.mark.asyncio
async def test_view_shared_note(client: AsyncClient, auth_headers: dict):
    mid = await _create_meeting_with_blocks(client, auth_headers)
    share_resp = await client.post(
        f"/meetings/{mid}/share", json={}, headers=auth_headers
    )
    token = share_resp.json()["token"]

    # No auth needed to view shared note
    resp = await client.get(f"/share/{token}")
    assert resp.status_code == 200
    data = resp.json()
    assert data["meeting"]["title"] == "Shareable"
    assert len(data["blocks"]) == 1


@pytest.mark.asyncio
async def test_expired_share_link(client: AsyncClient, auth_headers: dict):
    mid = await _create_meeting_with_blocks(client, auth_headers)
    resp = await client.post(
        f"/meetings/{mid}/share",
        json={"expires_in_hours": -1},
        headers=auth_headers,
    )
    # -1 hours means already expired
    token = resp.json()["token"]
    resp = await client.get(f"/share/{token}")
    assert resp.status_code == 410


@pytest.mark.asyncio
async def test_invalid_share_token(client: AsyncClient):
    resp = await client.get("/share/invalid-token")
    assert resp.status_code == 404
```

- [ ] **Step 5: Run tests**

```bash
uv run pytest tests/test_share.py -v
```

Expected: 4 tests pass.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: share links for meeting notes"
```

---

### Task 8: Seed Data + Full Test Suite

**Files:**
- Create: `src/vaakya/seed.py`
- Create: `tests/test_health.py`

- [ ] **Step 1: Create seed script**

Write `src/vaakya/seed.py`:
```python
import asyncio
from datetime import datetime, timezone

from vaakya.db import async_session, engine
from vaakya.models import Base, Block, Meeting, User


async def seed():
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

    async with async_session() as db:
        user = User(
            email="demo@vaakya.ai",
            name="Demo User",
            provider="google",
            provider_id="demo-001",
        )
        db.add(user)
        await db.flush()

        meeting = Meeting(
            user_id=user.id,
            title="Weekly Standup",
            started_at=datetime(2026, 3, 31, 15, 30, tzinfo=timezone.utc),
            ended_at=datetime(2026, 3, 31, 15, 58, tzinfo=timezone.utc),
            duration_seconds=1680,
            speaker_count=4,
            transcript=(
                "[0:00] Priya: Alright everyone, first item — release cadence.\n"
                "[0:32] Amit: Agreed. Features sitting in staging over a week.\n"
                "[1:05] Priya: We need to ship faster or we lose the Acme Corp deal.\n"
                "[1:38] Ravi: CI pipeline updated by Friday if we freeze feature work.\n"
                "[2:15] You: Makes sense. Also document rollback process.\n"
            ),
            template="standup",
        )
        db.add(meeting)
        await db.flush()

        blocks = [
            Block(meeting_id=meeting.id, type="summary", content="Team agreed to move from bi-weekly to weekly releases. Primary driver is Acme Corp deal. Ravi leads CI pipeline changes.", position=0),
            Block(meeting_id=meeting.id, type="decision", content="Move to weekly releases starting next sprint", speaker="Priya", meta_text="Unanimous", position=1),
            Block(meeting_id=meeting.id, type="decision", content="Freeze feature work this week for CI/CD", speaker="Ravi", position=2),
            Block(meeting_id=meeting.id, type="action", content="Update CI pipeline for weekly releases", speaker="Ravi", meta_text="Due Friday", position=3),
            Block(meeting_id=meeting.id, type="action", content="Document rollback process", speaker="Ravi", position=4),
            Block(meeting_id=meeting.id, type="action", content="Draft Q2 release schedule", speaker="Priya", meta_text="Due Monday", position=5),
            Block(meeting_id=meeting.id, type="quote", content="We need to ship faster or we're going to lose the deal with Acme Corp.", speaker="Priya", timestamp_seconds=65, position=6),
            Block(meeting_id=meeting.id, type="quote", content="I can have the CI pipeline updated by Friday if we freeze feature work.", speaker="Ravi", timestamp_seconds=98, position=7),
        ]
        db.add_all(blocks)
        await db.commit()

    print("Seeded: 1 user, 1 meeting, 8 blocks")
    await engine.dispose()


if __name__ == "__main__":
    asyncio.run(seed())
```

- [ ] **Step 2: Create health test**

Write `tests/test_health.py`:
```python
import pytest
from httpx import AsyncClient


@pytest.mark.asyncio
async def test_health(client: AsyncClient):
    resp = await client.get("/health")
    assert resp.status_code == 200
    data = resp.json()
    assert data["status"] == "ok"
```

- [ ] **Step 3: Run full test suite**

```bash
uv run pytest -v
```

Expected: All tests pass (health + auth + meetings + notes + enhance + share).

- [ ] **Step 4: Run seed**

```bash
make up
make migrate
make seed
```

- [ ] **Step 5: Manual smoke test**

```bash
uv run uvicorn vaakya.main:app --env-file .env.dev --port 8000 &
sleep 2

# Login
TOKEN=$(curl -s -X POST http://localhost:8000/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"demo@vaakya.ai","name":"Demo","provider":"google","provider_id":"demo-001"}' \
  | python -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

# List meetings
curl -s http://localhost:8000/meetings -H "Authorization: Bearer $TOKEN" | python -m json.tool

# Get blocks
MEETING_ID=$(curl -s http://localhost:8000/meetings -H "Authorization: Bearer $TOKEN" | python -c "import sys,json; print(json.load(sys.stdin)[0]['id'])")
curl -s "http://localhost:8000/meetings/$MEETING_ID/blocks" -H "Authorization: Bearer $TOKEN" | python -m json.tool

kill %1
```

Expected: Meeting and 8 blocks returned.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: seed data and full test suite"
```

---

## Summary

| Task | What it builds | Endpoints |
|---|---|---|
| 1 | Project scaffold, Docker Compose, config | `GET /health` |
| 2 | Database models, Alembic migrations | — |
| 3 | Auth (JWT login, /me) | `POST /auth/login`, `GET /auth/me` |
| 4 | Meetings CRUD | `POST/GET/PATCH/DELETE /meetings` |
| 5 | Blocks (Notes) CRUD | `POST/GET/PATCH/DELETE /meetings/{id}/blocks` |
| 6 | AI Enhancement | `POST /meetings/{id}/enhance` |
| 7 | Share Links | `POST /meetings/{id}/share`, `GET /share/{token}` |
| 8 | Seed data, full test suite | — |

After this plan: the backend runs fully local with `make up && make dev`. Next plan will cover the Swift/SwiftUI client.
