"""Etat live d'une seance : ce que les machines Technogym ont deja enregistre aujourd'hui.

La montre interroge GET /workout/{id}/live toutes les 20 a 30 s pendant la seance. Le backend cherche la
seance performee du jour pour cette seance prescrite (ActivityHistory puis GetPerformedWorkoutSessionByIdCr)
et renvoie, par position, le statut (done / todo) et les series reelles (reps, charge) enregistrees par les
machines ou par l'app Mywellness. La montre marque ces exercices comme faits et saute au suivant.
"""

from __future__ import annotations

import threading
import time
from datetime import date
from typing import Any

from pydantic import BaseModel, Field

from app.mywellness import client as mw
from app.mywellness.history import parse_performed_exercise
from app.mywellness.models import partition_iso


class LiveSet(BaseModel):
    reps: int | None = None
    weight_kg: float | None = None
    duration_s: int | None = None


class LiveExercise(BaseModel):
    position: int
    name: str = ""
    status: str = "todo"  # done | todo | partial
    source: str = ""      # machine | manual
    done_on: str = ""
    sets: list[LiveSet] = Field(default_factory=list)


class LiveState(BaseModel):
    workout_id: str
    date: str
    session_found: bool = False
    id_cr: int | None = None
    started_on: str = ""
    closed: bool = False
    done_count: int = 0
    total_count: int = 0
    exercises: list[LiveExercise] = Field(default_factory=list)
    fetched_at: int = 0


class LiveService:
    def __init__(self, client: mw.MywellnessClient | None, ttl: int = 15):
        self._client = client
        self._ttl = ttl
        self._lock = threading.RLock()
        self._cache: dict[str, tuple[float, LiveState]] = {}

    def state(self, workout_id: str, day: date | None = None) -> LiveState:
        day = day or date.today()
        key = f"{workout_id}:{day.isoformat()}"
        with self._lock:
            hit = self._cache.get(key)
            if hit and time.time() - hit[0] < self._ttl:
                return hit[1]
        st = self._fetch(workout_id, day)
        with self._lock:
            self._cache[key] = (time.time(), st)
        return st

    def _fetch(self, workout_id: str, day: date) -> LiveState:
        st = LiveState(workout_id=workout_id, date=day.isoformat(), fetched_at=int(time.time()))
        if self._client is None:
            return st
        items = self._client.activity_history(day, day)
        item = next((i for i in items if str(i.get("userWorkoutSessionId")) == workout_id and partition_iso(i.get("partitionDate")) == day.isoformat()), None)
        if item is None or item.get("idCr") in (None, ""):
            return st
        raw = self._client.performed_session_raw(item["idCr"], str(item["partitionDate"]), item.get("facilityId"))
        st.session_found = True
        st.id_cr = int(item["idCr"])
        st.started_on = str(raw.get("startedOn") or "")
        st.closed = bool(raw.get("closedOn"))
        for act in raw.get("physicalActivities") or []:
            ex = parse_performed_exercise(act)
            pa = act.get("performedPhysicalActivity") or {}
            status = "done" if str(act.get("status")) == "Done" else ("partial" if act.get("hasBeenDonePartially") else "todo")
            st.exercises.append(
                LiveExercise(
                    position=int(act.get("position") or 0),
                    name=ex.name,
                    status=status,
                    source=("manual" if pa.get("manuallyDone") else ("machine" if pa else "")),
                    done_on=ex.done_on,
                    sets=[LiveSet(reps=s.reps, weight_kg=s.weight_kg, duration_s=s.duration_s) for s in ex.sets if (s.reps, s.weight_kg, s.duration_s) != (None, None, None)],
                )
            )
        st.total_count = len(st.exercises)
        st.done_count = sum(1 for e in st.exercises if e.status == "done")
        return st
