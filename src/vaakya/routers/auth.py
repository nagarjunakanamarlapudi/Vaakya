import json
import logging

from fastapi import APIRouter

from vaakya.deps import CurrentUserClaims

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/auth", tags=["auth"])


@router.get("/me")
async def me(claims: CurrentUserClaims):
    """Return user info from Firebase JWT claims — no DB lookup, stateless."""
    user_id = claims.get("sub") or claims.get("user_id", "")

    # Firebase JWT nested fields are flattened to JSON strings by API Gateway
    firebase_raw = claims.get("firebase", "{}")
    if isinstance(firebase_raw, str):
        try:
            firebase = json.loads(firebase_raw)
        except (json.JSONDecodeError, TypeError):
            firebase = {}
    else:
        firebase = firebase_raw

    sign_in_provider = firebase.get("sign_in_provider", "")
    if "google" in sign_in_provider:
        provider = "google"
    elif "apple" in sign_in_provider:
        provider = "apple"
    else:
        provider = sign_in_provider or claims.get("provider", "unknown")

    return {
        "id": user_id,
        "email": claims.get("email", ""),
        "name": claims.get("name", ""),
        "provider": provider,
        "avatar_url": claims.get("picture", ""),
    }
