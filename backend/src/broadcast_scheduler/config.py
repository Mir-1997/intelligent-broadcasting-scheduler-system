"""Application settings, loaded from ``backend/.env`` and environment variables."""

from functools import lru_cache
from pathlib import Path
from typing import Literal

from pydantic import Field
from pydantic_settings import (
    BaseSettings,
    PydanticBaseSettingsSource,
    SettingsConfigDict,
)

# backend/.env, resolved from this file so it is found whatever the working directory.
ENV_FILE = Path(__file__).resolve().parents[2] / ".env"


class Settings(BaseSettings):
    """Runtime configuration.

    Precedence (highest first): constructor arguments, ``backend/.env``, environment
    variables (case-insensitive, e.g. ``MAX_MATCH_RADIUS_MILES=3``), then field defaults.

    ``.env`` deliberately beats the environment: this project's file must win over
    variables such as ``GOOGLE_APPLICATION_CREDENTIALS`` or ``GCP_PROJECT_ID`` that a
    shell profile exports for other projects. Without a ``.env`` (Docker, CI) the
    environment applies as usual.
    """

    model_config = SettingsConfigDict(env_file=ENV_FILE, env_file_encoding="utf-8", extra="ignore")

    @classmethod
    def settings_customise_sources(
        cls,
        settings_cls: type[BaseSettings],
        init_settings: PydanticBaseSettingsSource,
        env_settings: PydanticBaseSettingsSource,
        dotenv_settings: PydanticBaseSettingsSource,
        file_secret_settings: PydanticBaseSettingsSource,
    ) -> tuple[PydanticBaseSettingsSource, ...]:
        return init_settings, dotenv_settings, env_settings, file_secret_settings

    app_name: str = "Intelligent Broadcasting Scheduler"

    # --- Storage -------------------------------------------------------------------------
    storage_backend: Literal["firestore", "memory"] = Field(
        default="firestore",
        description="'firestore' for real persistence, 'memory' for a throwaway in-process store.",
    )
    gcp_project_id: str = Field(
        default="demo-broadcast-scheduler",
        description="Firebase/GCP project id. A 'demo-' prefix keeps the emulator fully offline.",
    )
    firestore_emulator_host: str | None = Field(
        default="localhost:8080",
        description="host:port of the Firestore emulator. Set to an empty string to use a real "
        "project (credentials come from GOOGLE_APPLICATION_CREDENTIALS / ADC).",
    )
    google_application_credentials: str | None = Field(
        default=None,
        description="Path to a service-account JSON key for a real project. When unset, "
        "Application Default Credentials are used. Ignored when using the emulator.",
    )
    firestore_database: str = "(default)"
    collection_prefix: str = Field(
        default="",
        description="Prepended to every collection name; useful for isolating test runs.",
    )

    # --- Matching ------------------------------------------------------------------------
    max_match_radius_miles: float = Field(default=5.0, gt=0)

    # --- Admin seed (used only when no admin document exists yet) ------------------------
    admin_name: str = "Admin HQ"
    admin_lat: float = Field(default=40.7580, ge=-90, le=90)
    admin_lng: float = Field(default=-73.9855, ge=-180, le=180)

    # --- HTTP ----------------------------------------------------------------------------
    cors_origins: list[str] = Field(default_factory=lambda: ["*"])
    websocket_queue_size: int = Field(
        default=1000,
        gt=0,
        description="Max undelivered events per WebSocket client before it is disconnected.",
    )


@lru_cache
def get_settings() -> Settings:
    """Return the process-wide settings instance."""
    return Settings()
