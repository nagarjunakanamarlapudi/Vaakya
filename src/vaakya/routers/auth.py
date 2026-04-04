import logging
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, HTTPException, Request
from jose import jwt
from pydantic import BaseModel
from slowapi import Limiter
from slowapi.util import get_remote_address

from vaakya.config import settings
from vaakya.deps import CurrentUserId
from vaakya.services.oauth import OAuthError, verify_apple_identity_token, verify_google_id_token

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/auth", tags=["auth"])
limiter = Limiter(key_func=get_remote_address, enabled=settings.rate_limiting_enabled)


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
@limiter.limit("10/minute")
async def login(request: Request, body: OAuthLoginRequest):
    if settings.skip_verification:
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


@router.get("/me")
async def me(user_id: CurrentUserId):
    """Return user info from JWT — no DB lookup, stateless."""
    return {
        "id": user_id,
        "email": f"{user_id}@vaakya.app",
        "name": user_id.split("-", 1)[-1] if "-" in user_id else user_id,
        "provider": user_id.split("-")[0] if "-" in user_id else "unknown",
        "avatar_url": None,
    }

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
    except HTTPException:
        raise
    except Exception:
        raise HTTPException(status_code=401, detail="Invalid refresh token")
    access, new_refresh = create_tokens(user_id)
    return TokenResponse(access_token=access, refresh_token=new_refresh)
