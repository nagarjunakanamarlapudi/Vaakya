from contextlib import asynccontextmanager

from fastapi import FastAPI

from vaakya.config import settings
from vaakya.db import engine


@asynccontextmanager
async def lifespan(app: FastAPI):
    yield
    await engine.dispose()


app = FastAPI(
    title="Vaakya API",
    version="0.1.0",
    lifespan=lifespan,
)


@app.get("/health")
async def health():
    return {"status": "ok", "env": settings.vaakya_env}
