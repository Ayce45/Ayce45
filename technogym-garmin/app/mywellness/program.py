"""Service "programme" : seance du jour, cache, secours YAML."""

from __future__ import annotations

import logging
import threading
import time
from datetime import date, datetime, timedelta
from pathlib import Path
from typing import Any

import yaml

from app.mywellness import client as mw
from app.mywellness.models import Exercise, SetTarget, Workout, build_workout, partition_iso

log = logging.getLogger(__name__)


class ProgramService:
    """Charge le programme prescrit et choisit la seance du jour.

    Regles (voir DECISIONS.md) :
      1. seance `workoutSessionStatus == "Suggested"` si presente ;
      2. sinon rotation cyclique apres la derniere seance performee ;
      3. sinon position 1.
    Une seance performee aujourd'hui reste la seance du jour.
    """

    def __init__(self, client: mw.MywellnessClient | None, cache_ttl: int = 300, override_path: Path | None = None):
        self._client = client
        self._ttl = cache_ttl
        self._override = override_path
        self._lock = threading.RLock()
        self._program: dict[str, Any] | None = None
        self._program_ts = 0.0
        self._details: dict[str, list[dict[str, Any]]] = {}
        self._details_ts: dict[str, float] = {}
        self._history: list[dict[str, Any]] | None = None
        self._history_ts = 0.0

    # ------------------------------------------------------------ acces bruts (caches)
    def program(self, force: bool = False) -> dict[str, Any]:
        with self._lock:
            if force or self._program is None or time.time() - self._program_ts > self._ttl:
                if self._client is None:
                    raise mw.MywellnessError("Client Mywellness non configure")
                self._program = self._client.user_training_program_raw()
                self._program_ts = time.time()
                self._details.clear()
            return self._program

    def sessions(self) -> list[dict[str, Any]]:
        return sorted(self.program().get("workoutSessions") or [], key=lambda s: int(s.get("position") or 0))

    def session_details(self, session: dict[str, Any], force: bool = False) -> list[dict[str, Any]]:
        sid = str(session["id"])
        with self._lock:
            if not force and sid in self._details and time.time() - self._details_ts.get(sid, 0) <= self._ttl:
                return self._details[sid]
            assert self._client is not None
            details = []
            for pa in session.get("physicalActivities") or []:
                try:
                    details.append(self._client.user_workout_session_physical_activity_raw(sid, int(pa["position"])))
                except mw.MywellnessError as exc:
                    log.warning("Detail exercice %s#%s indisponible (%s), on garde l'entree du programme", sid, pa.get("position"), exc)
                    details.append(pa)
            self._details[sid] = details
            self._details_ts[sid] = time.time()
            return details

    def recent_history(self, days: int = 120, force: bool = False) -> list[dict[str, Any]]:
        with self._lock:
            if force or self._history is None or time.time() - self._history_ts > self._ttl:
                assert self._client is not None
                today = date.today()
                self._history = self._client.activity_history(today - timedelta(days=days), today, only_workouts=True)
                self._history_ts = time.time()
            return self._history

    # ------------------------------------------------------------ selection
    def pick_session(self, day: date | None = None) -> dict[str, Any]:
        sessions = self.sessions()
        if not sessions:
            raise mw.NotFoundError("Le programme ne contient aucune seance")
        day = day or date.today()
        history = self.recent_history()
        by_id = {str(s["id"]): s for s in sessions}

        # seance performee aujourd'hui : elle reste la seance du jour
        for item in history:
            if partition_iso(item.get("partitionDate")) == day.isoformat() and str(item.get("userWorkoutSessionId")) in by_id:
                return by_id[str(item["userWorkoutSessionId"])]

        for s in sessions:
            if str(s.get("workoutSessionStatus") or "").lower() == "suggested":
                return s

        # rotation cyclique apres la derniere seance performee du programme
        for item in history:
            last = by_id.get(str(item.get("userWorkoutSessionId")))
            if last is not None:
                idx = sessions.index(last)
                return sessions[(idx + 1) % len(sessions)]
        return sessions[0]

    def workout_for(self, session: dict[str, Any], day: date | None = None) -> Workout:
        day = day or date.today()
        return build_workout(session, self.session_details(session), day.isoformat(), self.program())

    def today(self, day: date | None = None) -> Workout:
        override = self.load_override(day)
        if override is not None:
            return override
        return self.workout_for(self.pick_session(day), day)

    def by_id(self, workout_id: str) -> Workout | None:
        for s in self.sessions():
            if str(s.get("id")) == workout_id:
                return self.workout_for(s)
        return None

    def all_workouts(self) -> list[Workout]:
        return [self.workout_for(s) for s in self.sessions()]

    # ------------------------------------------------------------ secours YAML
    def load_override(self, day: date | None = None) -> Workout | None:
        """Fichier YAML optionnel decrivant la seance a la main (dernier recours si l'API casse).

        Format :
            name: Seance A
            exercises:
              - name: Leg press
                sets: [{reps: 10, weight_kg: 80, rest_s: 45}, ...]
        """
        if not self._override or not Path(self._override).exists():
            return None
        day = day or date.today()
        data = yaml.safe_load(Path(self._override).read_text(encoding="utf-8")) or {}
        exercises = []
        for i, ex in enumerate(data.get("exercises") or [], start=1):
            exercises.append(
                Exercise(
                    position=int(ex.get("position") or i),
                    name=str(ex.get("name") or f"Exercice {i}"),
                    equipment=str(ex.get("equipment") or ""),
                    kind=ex.get("kind") or "strength",
                    sets=[SetTarget(**s) for s in ex.get("sets") or []],
                )
            )
        return Workout(
            id=str(data.get("id") or "override"),
            date=day.isoformat(),
            name=str(data.get("name") or "Seance"),
            program_name=str(data.get("program_name") or "Programme manuel"),
            exercises=exercises,
            source="yaml",
        )


def now_iso() -> str:
    return datetime.now().astimezone().isoformat(timespec="seconds")
