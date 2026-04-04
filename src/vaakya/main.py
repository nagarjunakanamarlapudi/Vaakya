import logging

from fastapi import FastAPI, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded
from slowapi.util import get_remote_address

from vaakya.config import settings
from vaakya.routers import auth, enhance, share, sync

logger = logging.getLogger(__name__)

limiter = Limiter(
    key_func=get_remote_address,
    enabled=settings.rate_limiting_enabled,
)

app = FastAPI(title="Vaakya API", version="0.2.0")
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

# CORS — from YAML config
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.middleware("http")
async def security_headers(request: Request, call_next):
    response: Response = await call_next(request)
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    if settings.vaakya_env not in ("dev", "test"):
        response.headers["Strict-Transport-Security"] = "max-age=63072000; includeSubDomains"
    return response


# Routers -- only 4 (auth, enhance, share, sync)
app.include_router(auth.router)
app.include_router(enhance.router)
app.include_router(share.router)
app.include_router(sync.router)


@app.get("/health")
async def health():
    return {"status": "ok", "env": settings.vaakya_env, "version": "0.2.0"}
