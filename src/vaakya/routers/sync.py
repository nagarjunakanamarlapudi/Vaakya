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
    key: str  # e.g. "meetings/{id}/meeting.json" or "meetings/{id}/audio.m4a"


class PresignResponse(BaseModel):
    url: str
    expires_in: int = 300


def _get_s3_client():
    from botocore.config import Config
    kwargs: dict = {
        "region_name": settings.s3_region,
        "config": Config(signature_version="s3v4"),  # Force SigV4 for pre-signed URLs
    }
    if settings.s3_endpoint_url:
        kwargs["endpoint_url"] = settings.s3_endpoint_url
        kwargs["aws_access_key_id"] = settings.s3_access_key
        kwargs["aws_secret_access_key"] = settings.s3_secret_key
    return boto3.client("s3", **kwargs)


@router.post("/presign", response_model=PresignResponse)
async def presign(body: PresignRequest, user_id: CurrentUserId):
    """Generate a pre-signed S3 URL scoped to the user's prefix."""
    if body.action not in ("put", "get"):
        raise HTTPException(status_code=400, detail="action must be 'put' or 'get'")

    # Prevent path traversal
    if ".." in body.key or body.key.startswith("/") or "\\" in body.key:
        raise HTTPException(status_code=400, detail="Invalid key")

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
