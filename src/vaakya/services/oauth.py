"""OAuth token verification for Apple and Google identity providers."""

import logging

import httpx
from jose import jwt as jose_jwt
from jose.exceptions import JWTError

logger = logging.getLogger(__name__)

APPLE_JWKS_URL = "https://appleid.apple.com/auth/keys"
GOOGLE_TOKEN_URL = "https://oauth2.googleapis.com/tokeninfo"


class OAuthError(Exception):
    """Raised when OAuth token verification fails."""


async def verify_apple_identity_token(identity_token: str, client_id: str) -> dict:
    """Verify an Apple Sign In identity token (JWT).

    Fetches Apple's public JWKS, finds the matching key by kid, then
    decodes and verifies the token.

    Returns:
        dict with keys: sub, email
    Raises:
        OAuthError on any verification failure.
    """
    try:
        async with httpx.AsyncClient() as client:
            resp = await client.get(APPLE_JWKS_URL)
            resp.raise_for_status()
            jwks = resp.json()
    except httpx.HTTPError as exc:
        logger.error("Failed to fetch Apple JWKS: %s", exc)
        raise OAuthError("Failed to fetch Apple signing keys") from exc

    try:
        header = jose_jwt.get_unverified_header(identity_token)
    except JWTError as exc:
        raise OAuthError("Invalid Apple identity token format") from exc

    kid = header.get("kid")
    if not kid:
        raise OAuthError("Apple identity token missing key ID")

    key = next((k for k in jwks.get("keys", []) if k.get("kid") == kid), None)
    if not key:
        raise OAuthError("Apple signing key not found for kid=%s" % kid)

    try:
        payload = jose_jwt.decode(
            identity_token,
            key,
            algorithms=["RS256"],
            audience=client_id,
            issuer="https://appleid.apple.com",
        )
    except JWTError as exc:
        logger.warning("Apple token verification failed: %s", exc)
        raise OAuthError("Apple token verification failed: %s" % exc) from exc

    return {
        "sub": payload["sub"],
        "email": payload.get("email", ""),
    }


async def verify_google_id_token(id_token: str, client_id: str) -> dict:
    """Verify a Google Sign In ID token via Google's tokeninfo endpoint.

    Returns:
        dict with keys: sub, email, name, avatar_url
    Raises:
        OAuthError on any verification failure.
    """
    try:
        async with httpx.AsyncClient() as client:
            resp = await client.get(
                GOOGLE_TOKEN_URL, params={"id_token": id_token}
            )
            resp.raise_for_status()
            payload = resp.json()
    except httpx.HTTPError as exc:
        logger.error("Failed to verify Google token: %s", exc)
        raise OAuthError("Failed to verify Google token") from exc

    if payload.get("aud") != client_id:
        raise OAuthError(
            "Google token audience mismatch: expected %s, got %s"
            % (client_id, payload.get("aud"))
        )

    return {
        "sub": payload["sub"],
        "email": payload.get("email", ""),
        "name": payload.get("name", ""),
        "avatar_url": payload.get("picture", ""),
    }
