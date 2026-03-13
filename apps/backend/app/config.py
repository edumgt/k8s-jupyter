from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    app_name: str = "k8s-data-platform-api"
    env: str = "base"
    mongo_url: str = "mongodb://mongodb:27017/platform"
    redis_url: str = "redis://redis:6379/0"
    backend_url: str = "http://localhost:30081/docs"
    frontend_url: str = "http://localhost:30080"
    airflow_url: str = "http://localhost:30090"
    jupyter_url: str = "http://localhost:30088/lab"
    gitlab_url: str = "http://localhost:30089"
    harbor_url: str = "http://harbor.local:30083"
    notebooks_path: str = "/workspace/notebooks"
    teradata_host: str | None = None
    teradata_user: str | None = None
    teradata_password: str | None = None
    teradata_database: str = "dbc"
    teradata_fake_mode: bool = True
    teradata_encryptdata: bool = True

    model_config = SettingsConfigDict(
        env_prefix="PLATFORM_",
        env_file=".env",
        extra="ignore",
    )


@lru_cache
def get_settings() -> Settings:
    return Settings()
