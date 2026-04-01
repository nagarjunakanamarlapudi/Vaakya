from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    vaakya_env: str = "dev"
    database_url: str
    redis_url: str = "redis://localhost:6379/0"
    s3_endpoint_url: str = "http://localhost:9000"
    s3_access_key: str = "minioadmin"
    s3_secret_key: str = "minioadmin"
    s3_bucket: str = "vaakya-dev"
    jwt_secret: str = "dev-secret-change-in-prod"
    jwt_algorithm: str = "HS256"
    jwt_expire_minutes: int = 1440
    ai_provider: str = "ollama"
    ollama_base_url: str = "http://localhost:11434"

    model_config = {"env_file": ".env.dev", "extra": "ignore"}


settings = Settings()
