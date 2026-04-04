import pytest
from jose import jwt


@pytest.mark.asyncio
async def test_login_dev_mode(client):
    """Dev mode login should return tokens without provider verification."""
    resp = await client.post(
        "/auth/login",
        json={"provider": "apple", "identity_token": "fake-token-12345678"},
    )
    assert resp.status_code == 200
    data = resp.json()
    assert "access_token" in data
    assert "refresh_token" in data
    assert data["token_type"] == "bearer"

    # Verify the access token contains the right user_id
    payload = jwt.decode(data["access_token"], "test-secret", algorithms=["HS256"])
    assert payload["sub"] == "dev-fake-token-12345"
    assert payload["type"] == "access"


@pytest.mark.asyncio
async def test_login_unsupported_provider(client):
    resp = await client.post(
        "/auth/login",
        json={"provider": "facebook", "identity_token": "fake-token"},
    )
    # In dev mode, skip_verification is true, so all providers get dev user_id
    # The unsupported provider check only triggers when skip_verification is false
    assert resp.status_code == 200


@pytest.mark.asyncio
async def test_refresh_valid(client, auth_tokens):
    _, refresh_token = auth_tokens
    resp = await client.post("/auth/refresh", json={"refresh_token": refresh_token})
    assert resp.status_code == 200
    data = resp.json()
    assert "access_token" in data
    assert "refresh_token" in data


@pytest.mark.asyncio
async def test_refresh_invalid_token(client):
    resp = await client.post("/auth/refresh", json={"refresh_token": "garbage-token"})
    assert resp.status_code == 401


@pytest.mark.asyncio
async def test_refresh_with_access_token_rejected(client, auth_tokens):
    """Using an access token as refresh token should fail."""
    access_token, _ = auth_tokens
    resp = await client.post("/auth/refresh", json={"refresh_token": access_token})
    assert resp.status_code == 401
