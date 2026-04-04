import os
from functools import lru_cache
from pathlib import Path

import yaml

_stage = os.getenv("VAAKYA_ENV", "dev")

# Config path: check multiple locations (Lambda task root, source tree, relative)
_possible_paths = [
    Path(os.getenv("LAMBDA_TASK_ROOT", "")) / "infra" / "config" / f"{_stage}.yaml",
    Path(__file__).parent.parent.parent / "infra" / "config" / f"{_stage}.yaml",
    Path("infra") / "config" / f"{_stage}.yaml",
]
_config_path = next((p for p in _possible_paths if p.exists()), _possible_paths[-1])


def _load_yaml_config() -> dict:
    if _config_path.exists():
        with open(_config_path) as f:
            return yaml.safe_load(f)
    return {"env": _stage}


_yaml = _load_yaml_config()


@lru_cache(maxsize=20)
def _get_ssm_secret(path: str) -> str:
    """Fetch secret from SSM Parameter Store. Cached per Lambda cold start."""
    if _stage == "dev":
        # Dev mode: use env vars or dummy values
        return os.getenv(path.split("/")[-1].upper().replace("-", "_"), "dev-secret")
    try:
        import boto3

        client = boto3.client("ssm", region_name=_yaml.get("s3", {}).get("region", "us-east-1"))
        resp = client.get_parameter(Name=path, WithDecryption=True)
        return resp["Parameter"]["Value"]
    except Exception:
        return ""


class Settings:
    """App settings loaded from YAML config + SSM secrets."""

    vaakya_env: str = _yaml.get("env", "dev")

    # S3
    s3_bucket: str = _yaml.get("s3", {}).get("bucket", "vaakya-data-dev")
    s3_region: str = _yaml.get("s3", {}).get("region", "us-east-1")
    s3_endpoint_url: str = _yaml.get("s3", {}).get("endpoint_url", "")
    s3_access_key: str = _yaml.get("s3", {}).get("access_key", "")
    s3_secret_key: str = _yaml.get("s3", {}).get("secret_key", "")

    # AI
    ai_provider: str = _yaml.get("ai", {}).get("provider", "ollama")
    ollama_base_url: str = _yaml.get("ai", {}).get("ollama_base_url", "http://localhost:11434")

    # Auth
    skip_verification: bool = _yaml.get("auth", {}).get("skip_verification", False)

    # CORS
    cors_origins: list[str] = _yaml.get("cors", {}).get("origins", ["http://localhost:*"])

    # Rate limiting
    rate_limiting_enabled: bool = _yaml.get("rate_limiting", {}).get("enabled", False)

    # JWT (from SSM in prod, env var in dev)
    jwt_algorithm: str = "HS256"
    jwt_expire_minutes: int = 1440
    jwt_refresh_expire_minutes: int = 10080

    @property
    def jwt_secret(self) -> str:
        return os.getenv("JWT_SECRET", "") or _get_ssm_secret(f"/vaakya/{_stage}/jwt-secret")

    @property
    def share_secret(self) -> str:
        return os.getenv("SHARE_SECRET", "") or _get_ssm_secret(f"/vaakya/{_stage}/share-secret")

    @property
    def apple_team_id(self) -> str:
        return _get_ssm_secret(f"/vaakya/{_stage}/apple-team-id")

    @property
    def apple_key_id(self) -> str:
        return _get_ssm_secret(f"/vaakya/{_stage}/apple-key-id")

    @property
    def apple_private_key(self) -> str:
        return _get_ssm_secret(f"/vaakya/{_stage}/apple-private-key")

    @property
    def apple_client_id(self) -> str:
        return _get_ssm_secret(f"/vaakya/{_stage}/apple-client-id")

    @property
    def google_client_id(self) -> str:
        return _get_ssm_secret(f"/vaakya/{_stage}/google-client-id")


settings = Settings()
