import logging
from datetime import datetime, timedelta, timezone

import boto3
from botocore.exceptions import ClientError
from fastapi import APIRouter, HTTPException
from jose import JWTError, jwt
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
        settings.share_secret,
        algorithm="HS256",
    )
    return ShareResponse(token=token, url=f"/share/{token}", expires_at=expires_at.isoformat())


@router.get("/share/{token}")
async def resolve_share(token: str):
    """Verify share token and return pre-signed S3 URL for the meeting.json."""
    try:
        payload = jwt.decode(token, settings.share_secret, algorithms=["HS256"])
    except JWTError:
        raise HTTPException(status_code=404, detail="Invalid or expired share link")

    user_id = payload.get("user_id", "")
    meeting_id = payload.get("meeting_id", "")

    # Validate IDs don't contain path traversal
    for val in (user_id, meeting_id):
        if not val or ".." in val or "/" in val or "\\" in val:
            raise HTTPException(status_code=404, detail="Invalid share link")

    from botocore.config import Config
    s3_kwargs: dict = {
        "region_name": settings.s3_region,
        "config": Config(signature_version="s3v4"),
    }
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
    except ClientError as e:
        if e.response['Error']['Code'] == 'NoSuchKey':
            raise HTTPException(status_code=404, detail="Meeting not found")
        logger.error("S3 error resolving share: %s", e)
        raise HTTPException(status_code=500, detail="Failed to retrieve meeting")
    except Exception as e:
        logger.error("Unexpected error resolving share: %s", e)
        raise HTTPException(status_code=500, detail="Internal server error")

    return {"meeting_url": url, "user_id": user_id, "meeting_id": meeting_id}
