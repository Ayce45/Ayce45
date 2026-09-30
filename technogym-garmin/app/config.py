"""Configuration chargee depuis les variables d'environnement / .env."""

from __future__ import annotations

from functools import lru_cache
from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict

ROOT = Path(__file__).resolve().parent.parent


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=ROOT / ".env", env_file_encoding="utf-8", extra="ignore")

    mywellness_email: str = ""
    mywellness_password: str = ""

    garmin_email: str = ""
    garmin_password: str = ""
    garth_home: Path = ROOT / "data" / "garth"

    backend_host: str = "0.0.0.0"
    backend_port: int = 8000
    admin_token: str = ""
    database_path: Path = ROOT / "data" / "backend.sqlite3"

    tz: str = "Europe/Paris"
    push_hour: int = 6

    # Fichier YAML optionnel decrivant le programme a la main (secours si l'API ne repond plus)
    program_override_path: Path | None = None
    # Cache du programme prescrit (secondes)
    program_cache_ttl: int = 300
    # Debug / demo : force la date du jour (YYYY-MM-DD) pour /workout/today et le job
    today_override: str = ""
    # Rejeu (tests) : journal JSONL de scripts/poc_live.py servi par GET /live a la place de Technogym,
    # une capture toutes les LIVE_REPLAY_STEP secondes.
    live_replay_path: str = ""
    live_replay_step: float = 3.0


@lru_cache
def get_settings() -> Settings:
    return Settings()
