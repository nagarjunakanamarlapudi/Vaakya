import json
from typing import Annotated

from fastapi import Depends, HTTPException, Request

from vaakya.config import settings


async def get_current_user_id(request: Request) -> str:
    """Extract user ID from Firebase JWT claims (verified by API Gateway or locally)."""
    claims = await get_current_user_claims(request)
    return claims.get("sub") or claims.get("user_id", "")


async def get_current_user_claims(request: Request) -> dict:
    """Extract Firebase JWT claims from API Gateway authorizer or dev-mode header."""
    if settings.skip_verification:
        return {"sub": "dev-user", "email": "dev@vaakya.app", "name": "Dev User"}

    # Production: API Gateway JWT authorizer already verified the token.
    # Claims are in the event context, passed through by Mangum.
    event = request.scope.get("aws.event", {})
    claims = (
        event.get("requestContext", {})
        .get("authorizer", {})
        .get("jwt", {})
        .get("claims", {})
    )
    if claims.get("sub") or claims.get("user_id"):
        return claims

    raise HTTPException(status_code=401, detail="Missing authentication")


CurrentUserId = Annotated[str, Depends(get_current_user_id)]
CurrentUserClaims = Annotated[dict, Depends(get_current_user_claims)]
