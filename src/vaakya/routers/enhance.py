import logging

from fastapi import APIRouter, Request
from pydantic import BaseModel
from slowapi import Limiter
from slowapi.util import get_remote_address

from vaakya.config import settings
from vaakya.deps import CurrentUserId
from vaakya.services.ai import enhance_meeting

logger = logging.getLogger(__name__)
router = APIRouter(tags=["enhance"])
limiter = Limiter(key_func=get_remote_address, enabled=settings.rate_limiting_enabled)


class EnhanceRequest(BaseModel):
    model_config = {"extra": "forbid"}
    transcript: str
    user_notes: str = ""
    template: str = "general"


class BlockResult(BaseModel):
    type: str
    content: str
    speaker: str | None = None
    meta_text: str | None = None


class EnhanceResponse(BaseModel):
    blocks: list[BlockResult]


@router.post("/enhance", response_model=EnhanceResponse)
@limiter.limit("5/minute")
async def enhance(request: Request, body: EnhanceRequest, user_id: CurrentUserId):
    logger.info("Enhance request: user=%s template=%s transcript_len=%d", user_id, body.template, len(body.transcript))
    blocks = await enhance_meeting(
        transcript=body.transcript,
        user_notes=body.user_notes,
        template=body.template,
        provider=settings.ai_provider,
        api_key=None,
        ollama_model=None,
        ollama_base_url=settings.ollama_base_url,
    )
    return EnhanceResponse(
        blocks=[
            BlockResult(type=b["type"], content=b["content"], speaker=b.get("speaker"), meta_text=b.get("meta_text"))
            for b in blocks
        ]
    )
