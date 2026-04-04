import json
import re

import httpx

from vaakya.config import settings

ENHANCE_PROMPT = """You are a meeting notes assistant. Analyze this meeting transcript and produce structured notes.

IMPORTANT: You MUST respond with ONLY a valid JSON array. No code, no explanations, no markdown.

Each element in the array must have these fields:
- "type": "summary" or "decision" or "action" or "quote"
- "content": a clear sentence describing what was said or decided
- "speaker": the person's name (use null for summary)
- "timestamp_seconds": null
- "meta_text": null

Example output for a short meeting:
[
  {{"type": "summary", "content": "The team discussed project deadlines and assigned tasks.", "speaker": null, "timestamp_seconds": null, "meta_text": null}},
  {{"type": "decision", "content": "Launch date set for April 15th.", "speaker": "Sarah", "timestamp_seconds": null, "meta_text": "Agreed by all"}},
  {{"type": "action", "content": "Prepare the launch presentation.", "speaker": "Mike", "timestamp_seconds": null, "meta_text": "Due next Monday"}},
  {{"type": "quote", "content": "We need to move fast on this.", "speaker": "Sarah", "timestamp_seconds": null, "meta_text": null}}
]

Now analyze this transcript and return ONLY a JSON array like the example above:

<transcript>
{transcript}
</transcript>

<user_notes>
{user_notes}
</user_notes>

Template style: {template}

Respond with ONLY the JSON array. Nothing else."""

CHAT_PROMPT = """You are a meeting notes assistant. The user is asking a question about a meeting transcript.

<transcript>
{transcript}
</transcript>

<user_question>
{message}
</user_question>

Provide a clear, concise answer based only on the transcript. If the answer is not in the transcript, say so.
Respond in plain text, not JSON."""

AI_TIMEOUT = 120.0


def _parse_json_response(text: str) -> list[dict]:
    """Parse JSON from AI responses, handling markdown fencing and extra text."""
    cleaned = text.strip()

    # Strip markdown code fences: ```json ... ``` or ``` ... ```
    fence_pattern = re.compile(r"```(?:json)?\s*\n?(.*?)\n?\s*```", re.DOTALL)
    match = fence_pattern.search(cleaned)
    if match:
        cleaned = match.group(1).strip()

    # Try direct parse
    try:
        parsed = json.loads(cleaned)
        if isinstance(parsed, list):
            return parsed
        if isinstance(parsed, dict):
            # Some models wrap in {"blocks": [...]} or {"results": [...]}
            for key in ("blocks", "results", "notes", "data"):
                if key in parsed and isinstance(parsed[key], list):
                    return parsed[key]
            # Single block dict -> wrap in list
            return [parsed]
        return [{"type": "summary", "content": str(parsed)}]
    except json.JSONDecodeError:
        pass

    # Try to find a JSON array in the text
    array_match = re.search(r"\[.*\]", cleaned, re.DOTALL)
    if array_match:
        try:
            parsed = json.loads(array_match.group())
            if isinstance(parsed, list):
                return parsed
        except json.JSONDecodeError:
            pass

    # Fallback: return raw text as a single summary block
    return [
        {
            "type": "summary",
            "content": text.strip(),
            "speaker": None,
            "timestamp_seconds": None,
            "meta_text": None,
        }
    ]


async def enhance_meeting(
    transcript: str,
    user_notes: str = "",
    template: str = "general",
    provider: str | None = None,
    api_key: str | None = None,
    ollama_model: str | None = None,
    ollama_base_url: str | None = None,
) -> list[dict]:
    active_provider = provider or settings.ai_provider
    model = ollama_model or "llama3.2"
    base_url = ollama_base_url or settings.ollama_base_url

    if active_provider == "ollama":
        return await _enhance_ollama(transcript, user_notes, template, model, base_url)
    elif active_provider == "openai":
        return await _enhance_openai(transcript, user_notes, template, api_key)
    elif active_provider == "anthropic":
        return await _enhance_anthropic(transcript, user_notes, template, api_key)
    else:
        return await _enhance_ollama(transcript, user_notes, template, model, base_url)


async def chat_with_transcript(
    transcript: str,
    message: str,
    provider: str | None = None,
    api_key: str | None = None,
    ollama_model: str | None = None,
    ollama_base_url: str | None = None,
) -> str:
    """Send a chat question about a transcript to the AI provider."""
    active_provider = provider or settings.ai_provider
    model = ollama_model or "llama3.2"
    base_url = ollama_base_url or settings.ollama_base_url

    if active_provider == "ollama":
        return await _chat_ollama(transcript, message, model, base_url)
    elif active_provider == "openai":
        return await _chat_openai(transcript, message, api_key)
    elif active_provider == "anthropic":
        return await _chat_anthropic(transcript, message, api_key)
    else:
        return await _chat_ollama(transcript, message, model, base_url)


# ---------------------------------------------------------------------------
# Ollama
# ---------------------------------------------------------------------------


async def _enhance_ollama(
    transcript: str,
    user_notes: str,
    template: str,
    model: str = "llama3.2",
    base_url: str | None = None,
) -> list[dict]:
    url = base_url or settings.ollama_base_url
    prompt = ENHANCE_PROMPT.format(
        transcript=transcript, user_notes=user_notes, template=template
    )

    # Try with JSON format mode first, retry without if it fails
    for attempt in range(2):
        async with httpx.AsyncClient(timeout=AI_TIMEOUT) as client:
            payload = {"model": model, "prompt": prompt, "stream": False}
            if attempt == 0:
                payload["format"] = "json"
            resp = await client.post(f"{url}/api/generate", json=payload)
            resp.raise_for_status()
            text = resp.json()["response"]
            result = _parse_json_response(text)

            # Validate: if the "summary" content looks like code, retry
            if result and len(result) == 1 and result[0].get("type") == "summary":
                content = result[0].get("content", "")
                if any(
                    kw in content
                    for kw in [
                        "import ",
                        "def ",
                        "class ",
                        "function ",
                        "```",
                        "print(",
                    ]
                ):
                    if attempt == 0:
                        continue  # Retry without JSON mode
                    # On second attempt, create a simple summary from the transcript
                    return _simple_enhance(transcript)
            return result

    return _simple_enhance(transcript)


def _simple_enhance(transcript: str) -> list[dict]:
    """Fallback: create basic structured notes from the transcript without AI."""
    lines = [line.strip() for line in transcript.strip().split("\n") if line.strip()]
    blocks = []

    # First block is always a summary
    all_text = " ".join(ln.split("] ", 1)[-1] if "]" in ln else ln for ln in lines)
    blocks.append(
        {
            "type": "summary",
            "content": all_text[:300] + ("..." if len(all_text) > 300 else ""),
            "speaker": None,
            "timestamp_seconds": None,
            "meta_text": "Auto-generated from transcript",
        }
    )

    # Each line becomes a quote
    for line in lines[:10]:
        text = line
        speaker = None
        if "] " in text:
            text = text.split("] ", 1)[1]
        if ": " in text:
            parts = text.split(": ", 1)
            if len(parts[0]) <= 30:
                speaker = parts[0]
                text = parts[1]
        blocks.append(
            {
                "type": "quote",
                "content": text,
                "speaker": speaker,
                "timestamp_seconds": None,
                "meta_text": None,
            }
        )

    return blocks


async def _chat_ollama(
    transcript: str,
    message: str,
    model: str = "llama3.2",
    base_url: str | None = None,
) -> str:
    url = base_url or settings.ollama_base_url
    prompt = CHAT_PROMPT.format(transcript=transcript, message=message)
    async with httpx.AsyncClient(timeout=AI_TIMEOUT) as client:
        resp = await client.post(
            f"{url}/api/generate",
            json={"model": model, "prompt": prompt, "stream": False},
        )
        resp.raise_for_status()
        return resp.json()["response"].strip()


# ---------------------------------------------------------------------------
# OpenAI
# ---------------------------------------------------------------------------


async def _enhance_openai(
    transcript: str, user_notes: str, template: str, api_key: str | None
) -> list[dict]:
    if not api_key:
        raise ValueError("No API key configured. Set it in Settings.")
    prompt = ENHANCE_PROMPT.format(
        transcript=transcript, user_notes=user_notes, template=template
    )
    async with httpx.AsyncClient(timeout=AI_TIMEOUT) as client:
        resp = await client.post(
            "https://api.openai.com/v1/chat/completions",
            headers={"Authorization": f"Bearer {api_key}"},
            json={
                "model": "gpt-4o",
                "messages": [{"role": "user", "content": prompt}],
                "response_format": {"type": "json_object"},
            },
        )
        resp.raise_for_status()
        content = resp.json()["choices"][0]["message"]["content"]
        return _parse_json_response(content)


async def _chat_openai(transcript: str, message: str, api_key: str | None) -> str:
    if not api_key:
        raise ValueError("No API key configured. Set it in Settings.")
    prompt = CHAT_PROMPT.format(transcript=transcript, message=message)
    async with httpx.AsyncClient(timeout=AI_TIMEOUT) as client:
        resp = await client.post(
            "https://api.openai.com/v1/chat/completions",
            headers={"Authorization": f"Bearer {api_key}"},
            json={
                "model": "gpt-4o",
                "messages": [{"role": "user", "content": prompt}],
            },
        )
        resp.raise_for_status()
        return resp.json()["choices"][0]["message"]["content"].strip()


# ---------------------------------------------------------------------------
# Anthropic
# ---------------------------------------------------------------------------


async def _enhance_anthropic(
    transcript: str, user_notes: str, template: str, api_key: str | None
) -> list[dict]:
    if not api_key:
        raise ValueError("No API key configured. Set it in Settings.")
    prompt = ENHANCE_PROMPT.format(
        transcript=transcript, user_notes=user_notes, template=template
    )
    async with httpx.AsyncClient(timeout=AI_TIMEOUT) as client:
        resp = await client.post(
            "https://api.anthropic.com/v1/messages",
            headers={
                "x-api-key": api_key,
                "anthropic-version": "2023-06-01",
                "content-type": "application/json",
            },
            json={
                "model": "claude-sonnet-4-6-20250514",
                "max_tokens": 4096,
                "messages": [{"role": "user", "content": prompt}],
            },
        )
        resp.raise_for_status()
        text = resp.json()["content"][0]["text"]
        return _parse_json_response(text)


async def _chat_anthropic(transcript: str, message: str, api_key: str | None) -> str:
    if not api_key:
        raise ValueError("No API key configured. Set it in Settings.")
    prompt = CHAT_PROMPT.format(transcript=transcript, message=message)
    async with httpx.AsyncClient(timeout=AI_TIMEOUT) as client:
        resp = await client.post(
            "https://api.anthropic.com/v1/messages",
            headers={
                "x-api-key": api_key,
                "anthropic-version": "2023-06-01",
                "content-type": "application/json",
            },
            json={
                "model": "claude-sonnet-4-6-20250514",
                "max_tokens": 4096,
                "messages": [{"role": "user", "content": prompt}],
            },
        )
        resp.raise_for_status()
        return resp.json()["content"][0]["text"].strip()
