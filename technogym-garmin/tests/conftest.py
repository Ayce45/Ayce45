"""Fixtures pytest : reponses Mywellness reelles anonymisees, client factice, app FastAPI de test."""

from __future__ import annotations

import json
import threading
from datetime import date, timedelta
from pathlib import Path
from typing import Any

import pytest

from app.api.main import build_state, create_app
from app.config import Settings
from app.mywellness import client as mw

FIXTURES = Path(__file__).parent / "fixtures"


def load(name: str) -> Any:
    return json.loads((FIXTURES / f"{name}.json").read_text(encoding="utf-8"))


@pytest.fixture(scope="session")
def program_raw() -> dict[str, Any]:
    return load("GetUserTrainingProgram")["data"]["userTrainingProgramDetails"]


@pytest.fixture(scope="session")
def details_raw() -> dict[str, Any]:
    return load("GetUserWorkoutSessionPhysicalActivity")


@pytest.fixture(scope="session")
def history_raw() -> list[dict[str, Any]]:
    return load("ActivityHistory")["data"]["items"]


@pytest.fixture(scope="session")
def performed_raw() -> dict[str, Any]:
    return load("GetPerformedWorkoutSessionByIdCr")["data"]


class FakeMywellness(mw.MywellnessClient):
    """Rejoue les fixtures sans reseau."""

    def __init__(self, program: dict[str, Any], details: dict[str, Any], history: list[dict[str, Any]], performed: dict[str, Any]):
        self._program = program
        self._details = details
        self._history = history
        self._performed = performed
        self.calls: list[str] = []
        self._lock = threading.RLock()
        self._user = mw.UserInfo(user_id="user", first_name="Test", measurement_system="Metric", culture="fr-FR",
                                 facilities=[mw.Facility(id="fac-1", url="testgym", name="Test Gym")])
        self._facility_url = "testgym"
        self.written: list[tuple[str, dict[str, Any]]] = []

    def login(self) -> mw.UserInfo:  # type: ignore[override]
        return self._user

    def post_action(self, action: str, content: dict[str, Any] | None = None, facility_url: str | None = None) -> Any:  # type: ignore[override]
        self.calls.append(action)
        content = content or {}
        if action == mw.USER_TRAINING_PROGRAM:
            return {"userTrainingProgramDetails": self._program}
        if action == mw.USER_WORKOUT_SESSION_PA:
            key = f"{content['userWorkoutSessionId']}#{content['position']}"
            return self._details[key]["data"]
        if action == mw.ACTIVITY_HISTORY:
            start, end = str(content.get("startDay")), str(content.get("endDay"))
            items = [i for i in self._history if start <= str(i.get("partitionDate")) <= end]
            if content.get("justThisType"):
                items = [i for i in items if i.get("type") == content["justThisType"]]
            return {"items": items}
        if action == mw.PERFORMED_SESSION_BY_IDCR:
            return self._performed
        if action == mw.CURRENT_WORKOUT_SESSION:
            return {"hasCurrentWorkout": False}
        if action in (mw.START_WORKOUT_SESSION, mw.SAVE_PERFORMED_PA, mw.CLOSE_WORKOUT_SESSION, mw.MARK_PA_DONE):
            self.written.append((action, content))
            if action == mw.START_WORKOUT_SESSION:
                return {"idCr": 4242, "partitionDate": "20260930"}
            return {"ok": True}
        raise mw.NotFoundError(action)


@pytest.fixture
def fake_client(program_raw, details_raw, history_raw, performed_raw) -> FakeMywellness:
    return FakeMywellness(program_raw, details_raw, history_raw, performed_raw)


@pytest.fixture
def settings(tmp_path: Path) -> Settings:
    return Settings(
        _env_file=None,  # type: ignore[call-arg]
        mywellness_email="x@example.com",
        mywellness_password="pw",
        garmin_email="",
        garmin_password="",
        admin_token="admin-secret",
        database_path=tmp_path / "test.sqlite3",
        garth_home=tmp_path / "garth",
    )


@pytest.fixture
def app_state(settings, fake_client):
    return build_state(settings, mywellness_client=fake_client)


@pytest.fixture
def client(app_state):
    from fastapi.testclient import TestClient

    app = create_app(app_state, with_scheduler=False)
    with TestClient(app) as c:
        yield c


@pytest.fixture
def today_in_fixtures(history_raw) -> date:
    """Un jour sans seance performee, juste apres la derniere seance des fixtures."""
    last = max(str(i.get("partitionDate")) for i in history_raw if i.get("type") == "WorkoutSession")
    return date(int(last[:4]), int(last[4:6]), int(last[6:8])) + timedelta(days=1)
