"""Client Garmin Connect base sur garminconnect (jetons persistes dans data/garmin_tokens.json)."""

from __future__ import annotations

import logging
import threading
from pathlib import Path
from typing import Any

log = logging.getLogger(__name__)


class GarminError(Exception):
    pass


class GarminClient:
    def __init__(self, email: str, password: str, token_dir: Path | str):
        if not email or not password:
            raise GarminError("GARMIN_EMAIL et GARMIN_PASSWORD doivent etre definis")
        self._email = email
        self._password = password
        self._token_dir = Path(token_dir)
        self._token_file = self._token_dir / "garmin_tokens.json"
        self._lock = threading.RLock()
        self._api: Any = None

    def _connect(self) -> Any:
        from garminconnect import Garmin

        self._token_dir.mkdir(parents=True, exist_ok=True)
        api = Garmin(self._email, self._password, return_on_mfa=True)
        status, _ = api.login(tokenstore=str(self._token_file) if self._token_file.exists() else None)
        if status == "needs_mfa":
            raise GarminError("Garmin demande un code MFA : lancez `python -m app.garmin.login` en interactif")
        try:
            api.client.dump(str(self._token_file))
        except Exception as exc:  # pragma: no cover
            log.warning("Impossible de sauver les jetons Garmin: %s", exc)
        return api

    @property
    def api(self) -> Any:
        with self._lock:
            if self._api is None:
                self._api = self._connect()
            return self._api

    def _call(self, fn: str, *args: Any, **kwargs: Any) -> Any:
        try:
            return getattr(self.api, fn)(*args, **kwargs)
        except Exception as exc:
            msg = str(exc)
            if "401" in msg or "403" in msg or "Unauthorized" in msg:
                log.warning("Session Garmin expiree, reconnexion (%s)", msg[:100])
                with self._lock:
                    self._api = None
                    if self._token_file.exists():
                        self._token_file.unlink()
                return getattr(self.api, fn)(*args, **kwargs)
            raise GarminError(msg) from exc

    # ---------------------------------------------------------------- workouts
    def list_workouts(self, limit: int = 100) -> list[dict[str, Any]]:
        return self._call("get_workouts", 0, limit)

    def get_workout(self, workout_id: int | str) -> dict[str, Any]:
        return self._call("get_workout_by_id", workout_id)

    def upload_workout(self, payload: dict[str, Any]) -> dict[str, Any]:
        return self._call("upload_workout", payload)

    def delete_workout(self, workout_id: int | str) -> Any:
        return self._call("delete_workout", workout_id)

    def schedule_workout(self, workout_id: int | str, day_iso: str) -> dict[str, Any]:
        return self._call("schedule_workout", workout_id, day_iso)

    def scheduled_workouts(self, start_iso: str, end_iso: str) -> list[dict[str, Any]]:
        return self._call("get_scheduled_workouts", start_iso, end_iso)

    def unschedule_workout(self, scheduled_id: int | str) -> Any:
        return self._call("unschedule_workout", scheduled_id)
