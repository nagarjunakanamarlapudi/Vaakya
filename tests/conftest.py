import os

# Set env vars before any app imports
os.environ["VAAKYA_ENV"] = "dev"
os.environ["JWT_SECRET"] = "test-secret"
os.environ["SHARE_SECRET"] = "test-share-secret"

import pytest
from httpx import ASGITransport, AsyncClient

from vaakya.main import app
from vaakya.routers.auth import create_tokens


@pytest.fixture
def anyio_backend():
    return "asyncio"


@pytest.fixture
async def client():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        yield ac


@pytest.fixture
def auth_headers():
    """Return Authorization headers with a valid access token."""
    access, _ = create_tokens("test-user-123")
    return {"Authorization": f"Bearer {access}"}


@pytest.fixture
def auth_tokens():
    """Return (access_token, refresh_token) for test-user-123."""
    return create_tokens("test-user-123")
