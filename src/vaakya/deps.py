from typing import Annotated

from fastapi import Depends, HTTPException, Header
from jose import JWTError, jwt

from vaakya.config import settings


async def get_current_user_id(authorization: Annotated[str, Header()] = "") -> str:
    """Extract user ID from JWT Bearer token. No DB lookup -- stateless."""
    if not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing auth token")
    token = authorization[7:]
    try:
        payload = jwt.decode(token, settings.jwt_secret, algorithms=[settings.jwt_algorithm])
        if payload.get("type") != "access":
            raise HTTPException(status_code=401, detail="Invalid token type")
        user_id = payload.get("sub")
        if not user_id:
            raise HTTPException(status_code=401, detail="Invalid token")
        return user_id
    except JWTError:
        raise HTTPException(status_code=401, detail="Invalid token")


CurrentUserId = Annotated[str, Depends(get_current_user_id)]
