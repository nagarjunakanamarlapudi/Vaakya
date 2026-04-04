import pytest
from unittest.mock import patch, MagicMock


@pytest.mark.asyncio
async def test_presign_put(client, auth_headers):
    mock_s3 = MagicMock()
    mock_s3.generate_presigned_url.return_value = "https://s3.example.com/presigned-put"

    with patch("vaakya.routers.sync.boto3") as mock_boto3:
        mock_boto3.client.return_value = mock_s3
        resp = await client.post(
            "/sync/presign",
            json={"action": "put", "key": "meetings/abc/meeting.json"},
            headers=auth_headers,
        )

    assert resp.status_code == 200
    data = resp.json()
    assert "url" in data
    assert data["expires_in"] == 300

    # Verify S3 was called with user-scoped key
    mock_s3.generate_presigned_url.assert_called_once_with(
        "put_object",
        Params={"Bucket": "vaakya-data-dev", "Key": "users/test-user-123/meetings/abc/meeting.json"},
        ExpiresIn=300,
    )


@pytest.mark.asyncio
async def test_presign_get(client, auth_headers):
    mock_s3 = MagicMock()
    mock_s3.generate_presigned_url.return_value = "https://s3.example.com/presigned-get"

    with patch("vaakya.routers.sync.boto3") as mock_boto3:
        mock_boto3.client.return_value = mock_s3
        resp = await client.post(
            "/sync/presign",
            json={"action": "get", "key": "meetings/abc/meeting.json"},
            headers=auth_headers,
        )

    assert resp.status_code == 200
    mock_s3.generate_presigned_url.assert_called_once_with(
        "get_object",
        Params={"Bucket": "vaakya-data-dev", "Key": "users/test-user-123/meetings/abc/meeting.json"},
        ExpiresIn=300,
    )


@pytest.mark.asyncio
async def test_presign_invalid_action(client, auth_headers):
    resp = await client.post(
        "/sync/presign",
        json={"action": "delete", "key": "meetings/abc/meeting.json"},
        headers=auth_headers,
    )
    assert resp.status_code == 400


@pytest.mark.asyncio
async def test_presign_requires_auth(client):
    resp = await client.post(
        "/sync/presign",
        json={"action": "get", "key": "meetings/abc/meeting.json"},
    )
    assert resp.status_code == 401


@pytest.mark.asyncio
async def test_index_url(client, auth_headers):
    mock_s3 = MagicMock()
    mock_s3.generate_presigned_url.return_value = "https://s3.example.com/index"

    with patch("vaakya.routers.sync.boto3") as mock_boto3:
        mock_boto3.client.return_value = mock_s3
        resp = await client.get("/sync/index", headers=auth_headers)

    assert resp.status_code == 200
    data = resp.json()
    assert "url" in data
    mock_s3.generate_presigned_url.assert_called_once_with(
        "get_object",
        Params={"Bucket": "vaakya-data-dev", "Key": "users/test-user-123/index.json"},
        ExpiresIn=300,
    )


@pytest.mark.asyncio
async def test_index_requires_auth(client):
    resp = await client.get("/sync/index")
    assert resp.status_code == 401
