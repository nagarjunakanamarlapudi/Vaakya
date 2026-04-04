import pytest
from unittest.mock import patch, MagicMock
from jose import jwt


@pytest.mark.asyncio
async def test_create_share(client, auth_headers):
    resp = await client.post(
        "/share",
        json={"meeting_id": "meeting-abc-123"},
        headers=auth_headers,
    )
    assert resp.status_code == 200
    data = resp.json()
    assert "token" in data
    assert "url" in data
    assert "expires_at" in data
    assert data["url"].startswith("/share/")


@pytest.mark.asyncio
async def test_create_share_custom_expiry(client, auth_headers):
    resp = await client.post(
        "/share",
        json={"meeting_id": "meeting-abc-123", "expires_in_hours": 24},
        headers=auth_headers,
    )
    assert resp.status_code == 200
    data = resp.json()
    assert "token" in data
    # Verify the token encodes the correct expiry
    payload = jwt.decode(data["token"], "test-share-secret", algorithms=["HS256"])
    assert payload["meeting_id"] == "meeting-abc-123"
    assert payload["user_id"] == "test-user-123"


@pytest.mark.asyncio
async def test_create_share_requires_auth(client):
    resp = await client.post("/share", json={"meeting_id": "meeting-abc-123"})
    assert resp.status_code == 401


@pytest.mark.asyncio
async def test_create_share_rejects_extra_fields(client, auth_headers):
    resp = await client.post(
        "/share",
        json={"meeting_id": "m1", "extra_field": "bad"},
        headers=auth_headers,
    )
    assert resp.status_code == 422


@pytest.mark.asyncio
async def test_create_share_requires_meeting_id(client, auth_headers):
    resp = await client.post("/share", json={}, headers=auth_headers)
    assert resp.status_code == 422


@pytest.mark.asyncio
async def test_resolve_share_valid(client, auth_headers):
    # First create a share token
    resp = await client.post(
        "/share",
        json={"meeting_id": "meeting-abc-123"},
        headers=auth_headers,
    )
    token = resp.json()["token"]

    # Mock S3 for resolve
    mock_s3 = MagicMock()
    mock_s3.generate_presigned_url.return_value = "https://s3.example.com/presigned"

    with patch("vaakya.routers.share.boto3") as mock_boto3:
        mock_boto3.client.return_value = mock_s3
        resp = await client.get(f"/share/{token}")

    assert resp.status_code == 200
    data = resp.json()
    assert "meeting_url" in data
    assert data["user_id"] == "test-user-123"
    assert data["meeting_id"] == "meeting-abc-123"


@pytest.mark.asyncio
async def test_share_e2e_create_and_resolve(client, auth_headers):
    """End-to-end: create share → resolve → verify S3 key constructed correctly."""
    # Step 1: Create share
    create_resp = await client.post(
        "/share",
        json={"meeting_id": "e2e-meeting-001"},
        headers=auth_headers,
    )
    assert create_resp.status_code == 200
    share_data = create_resp.json()
    token = share_data["token"]
    assert share_data["url"] == f"/share/{token}"

    # Step 2: Resolve share (mock S3 to capture the key it tries to fetch)
    mock_s3 = MagicMock()
    mock_s3.generate_presigned_url.return_value = "https://s3.example.com/e2e-presigned"

    with patch("vaakya.routers.share.boto3") as mock_boto3:
        mock_boto3.client.return_value = mock_s3
        resolve_resp = await client.get(f"/share/{token}")

    assert resolve_resp.status_code == 200
    resolve_data = resolve_resp.json()

    # Step 3: Verify the full chain
    assert resolve_data["meeting_url"] == "https://s3.example.com/e2e-presigned"
    assert resolve_data["user_id"] == "test-user-123"
    assert resolve_data["meeting_id"] == "e2e-meeting-001"

    # Verify S3 was asked for the correct user-scoped key
    mock_s3.generate_presigned_url.assert_called_once_with(
        "get_object",
        Params={
            "Bucket": "vaakya-data-dev",
            "Key": "users/test-user-123/meetings/e2e-meeting-001/meeting.json",
        },
        ExpiresIn=300,
    )


@pytest.mark.asyncio
async def test_resolve_share_invalid_token(client):
    resp = await client.get("/share/invalid-garbage-token")
    assert resp.status_code == 404


@pytest.mark.asyncio
async def test_resolve_share_expired_token(client):
    """Expired share token should return 404."""
    from datetime import datetime, timedelta, timezone

    expired_token = jwt.encode(
        {
            "user_id": "test-user",
            "meeting_id": "meeting-123",
            "exp": datetime.now(timezone.utc) - timedelta(hours=1),
        },
        "test-share-secret",
        algorithm="HS256",
    )
    resp = await client.get(f"/share/{expired_token}")
    assert resp.status_code == 404


@pytest.mark.asyncio
async def test_resolve_share_s3_error_returns_404(client, auth_headers):
    """When S3 presign fails (file doesn't exist), return 404."""
    from botocore.exceptions import ClientError

    resp = await client.post(
        "/share",
        json={"meeting_id": "nonexistent"},
        headers=auth_headers,
    )
    token = resp.json()["token"]

    mock_s3 = MagicMock()
    # Create a proper ClientError with NoSuchKey code
    error = ClientError(
        {"Error": {"Code": "NoSuchKey", "Message": "The specified key does not exist."}},
        "GetObject"
    )
    mock_s3.generate_presigned_url.side_effect = error

    with patch("vaakya.routers.share.boto3") as mock_boto3:
        mock_boto3.client.return_value = mock_s3
        resp = await client.get(f"/share/{token}")

    assert resp.status_code == 404
