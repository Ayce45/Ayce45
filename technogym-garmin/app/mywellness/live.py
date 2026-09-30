"""Etat live d'une seance : ce que les machines Technogym ont deja enregistre aujourd'hui.

La montre interroge GET /workout/{id}/live toutes les 20 a 30 s pendant la seance. Le backend cherche la
seance performee du jour pour cette seance prescrite (ActivityHistory puis GetPerformedWorkoutSessionByIdCr)
et renvoie, par position, le statut (done / todo) et les series reelles (reps, charge) enregistrees par les
machines ou par l'app Mywellness. La montre marque ces exercices comme faits et saute au suivant.
"""

from __future__ import annotations

import json

import threading
import time
from datetime import date, timedelta
from typing import Any

from pydantic import BaseModel, Field

from app.mywellness import client as mw
from app.mywellness.history import parse_performed_exercise
from app.mywellness.models import partition_iso


class LiveSet(BaseModel):
    reps: int | None = None
    weight_kg: float | None = None
    duration_s: int | None = None
    rest_s: int | None = None      # repos prescrit apres la serie (RestTime)


class LiveExercise(BaseModel):
    position: int
    name: str = ""
    short_name: str = ""
    equipment: str = ""
    kind: str = ""        # strength | cardio | stretching
    status: str = "todo"  # done | doing | todo | partial
    source: str = ""      # machine | manual
    device: str = ""      # FullConnected | Offline | ...
    done_on: str = ""
    sets: list[LiveSet] = Field(default_factory=list)            # series faites
    target_sets: list[LiveSet] = Field(default_factory=list)     # series prescrites
    done_move: int | None = None
    done_calories: int | None = None
    picture_url: str = ""            # visuel Technogym de l'exercice (cmsmedia / cdnmedia)
    equipment_picture_url: str = ""  # visuel de l'equipement
    muscles: list[str] = Field(default_factory=list)        # noms Technogym en francais
    muscle_types: list[str] = Field(default_factory=list)   # cles Technogym (Pectorals, Triceps...) pour la carte musculaire
    pa_id: str = ""                                          # physicalActivityId (cle stable de l'exercice)
    rm1_kg: float | None = None                              # 1RM estime par Technogym (currentReferenceValues)
    last_sets: list[LiveSet] = Field(default_factory=list)   # series de la derniere fois (historique)
    last_on: str = ""                                        # date de la derniere fois (YYYY-MM-DD)
    best_weight_kg: float | None = None                      # record de charge sur l'historique lu


class LiveState(BaseModel):
    workout_id: str
    date: str
    name: str = ""
    program_name: str = ""
    current_position: int | None = None   # premier exercice non fait (ou "Doing")
    hr_samples: int = 0                   # echantillons cardio deja recus de la montre pour cette seance
    has_current_workout: bool | None = None   # workout.mywellness.com/v2/enduser/workout/current
    current: dict | None = None               # seance courante brute si une machine / kiosque l'a ouverte
    session_found: bool = False
    id_cr: int | None = None
    started_on: str = ""
    closed: bool = False
    done_count: int = 0
    total_count: int = 0
    exercises: list[LiveExercise] = Field(default_factory=list)
    fetched_at: int = 0


def _steps_to_sets(steps: list[dict[str, Any]] | None) -> list[LiveSet]:
    out: list[LiveSet] = []
    for step in steps or []:
        v = {p.get("physicalProperty") or p.get("name"): p.get("value") for p in (step.get("properties") or step.get("data") or step.get("stepData") or [])}
        reps = v.get("IsoReps", v.get("Reps"))
        weight = v.get("IsoWeight", v.get("Weight"))
        dur = v.get("Duration")
        rest = v.get("RestTime", v.get("Rest"))
        if reps is not None or weight is not None or dur is not None:
            out.append(LiveSet(reps=int(reps) if reps is not None else None, weight_kg=weight, duration_s=int(dur) if dur is not None else None,
                               rest_s=int(rest) if rest is not None else None))
    return out


def _rm1(refs: Any) -> float | None:
    for r in refs or []:
        if isinstance(r, dict) and str(r.get("name") or "").lower() == "rm1" and r.get("value") is not None:
            try:
                return round(float(r["value"]), 1)
            except (TypeError, ValueError):
                return None
    return None


def _kind(pa_type: str, is_cardio: bool) -> str:
    t = (pa_type or "").lower()
    if is_cardio or t.startswith("cardio"):
        return "cardio"
    if t.startswith("stretch"):
        return "stretching"
    return "strength"


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

    # ------------------------------------------------------------------ rejeu (tests sans salle)
    _replay: list[dict[str, Any]] | None = None
    _replay_t0: float = 0.0
    replay_path: str = ""
    replay_step: float = 3.0

    def _replay_snapshot(self) -> dict[str, Any] | None:
        """Sert les captures GetCurrentWorkoutSession d'un journal poc_live.py, dans l'ordre, une par pas."""
        if not self.replay_path:
            return None
        if self._replay is None:
            snaps: list[dict[str, Any]] = []
            try:
                for line in open(self.replay_path, encoding="utf-8"):
                    try:
                        rec = json.loads(line)
                    except ValueError:
                        continue
                    cur = rec.get("current")
                    if isinstance(cur, dict):
                        snaps.append(cur)
            except OSError:
                snaps = []
            self._replay = snaps
            self._replay_t0 = time.time()
        if not self._replay:
            return {}
        idx = min(int((time.time() - self._replay_t0) / max(self.replay_step, 0.5)), len(self._replay) - 1)
        return self._replay[idx]

    # ------------------------------------------------------------------ historique par exercice
    _prev: dict[str, Any] | None = None
    _prev_at: float = 0.0
    PREV_TTL = 600.0
    PREV_DAYS = 90
    PREV_SESSIONS = 8

    def previous_by_exercise(self) -> dict[str, dict[str, Any]]:
        """Derniere execution et record de charge par exercice (cle : physicalActivityId, puis nom), lus dans
        les dernieres seances performees. Cache 10 min."""
        if self._prev is not None and time.time() - self._prev_at < self.PREV_TTL:
            return self._prev
        out: dict[str, dict[str, Any]] = {}
        if self._client is not None:
            try:
                today = date.today()
                items = self._client.activity_history(today - timedelta(days=self.PREV_DAYS), today)
                for item in items[: self.PREV_SESSIONS]:
                    try:
                        raw = self._client.performed_session_raw(item.get("idCr"), str(item.get("partitionDate")), item.get("facilityId"))
                    except mw.MywellnessError:
                        continue
                    day = str(item.get("partitionDate"))
                    day_iso = f"{day[:4]}-{day[4:6]}-{day[6:8]}" if len(day) == 8 else day
                    for act in raw.get("physicalActivities") or []:
                        pa = act.get("performedPhysicalActivity") or {}
                        steps = ((pa.get("data") or {}).get("steps")) or []
                        sets = _steps_to_sets(steps)
                        if not sets:
                            continue
                        best = max((s.weight_kg or 0.0) for s in sets)
                        for key in (str(act.get("physicalActivityId") or ""), str(act.get("physicalActivityName") or "")):
                            if not key:
                                continue
                            cur = out.get(key)
                            if cur is None:
                                out[key] = {"last_sets": sets, "last_on": day_iso, "best": best}
                            else:
                                cur["best"] = max(cur["best"], best)
            except mw.MywellnessError:
                pass
        self._prev = out
        self._prev_at = time.time()
        return out

    def _fill_previous(self, st: LiveState) -> None:
        prev = self.previous_by_exercise()
        if not prev:
            return
        for ex in st.exercises:
            p = prev.get(ex.pa_id) or prev.get(ex.name) or prev.get(ex.short_name)
            if p:
                ex.last_sets = p["last_sets"]
                ex.last_on = p["last_on"]
                ex.best_weight_kg = p["best"] or None

    def current(self) -> LiveState:
        """Seance courante cote Technogym, quelle qu'elle soit (bornes, machines, app). Cache court."""
        key = "__current__"
        with self._lock:
            hit = self._cache.get(key)
            if hit and time.time() - hit[0] < self._ttl:
                return hit[1]
        st = LiveState(workout_id="", date=date.today().isoformat(), fetched_at=int(time.time()))
        replay = self._replay_snapshot()
        if replay is not None or self._client is not None:
            if replay is not None:
                cur: Any = replay
            else:
                try:
                    cur = self._client.current_workout_session()  # type: ignore[union-attr]
                except mw.MywellnessError:
                    cur = {}
            ws = cur.get("workoutSession") if isinstance(cur, dict) else None
            if isinstance(ws, dict) and ws.get("exercises"):
                st.workout_id = str(ws.get("workoutSessionId") or "")
                st = self._from_current(ws, st)
            else:
                st.has_current_workout = False
        with self._lock:
            self._cache[key] = (time.time(), st)
        return st

    def _from_current(self, ws: dict[str, Any], st: LiveState) -> LiveState:
        """Etat live depuis GetCurrentWorkoutSession (seance ouverte). Verifie sur seance reelle le 2026-09-30."""
        st.has_current_workout = True
        st.session_found = True
        st.id_cr = int(ws.get("idCr") or 0) or None
        st.started_on = str(ws.get("startedOn") or "")
        st.closed = False
        st.name = str(ws.get("name") or "")
        st.program_name = str((ws.get("extData") or {}).get("mwc_workout_name") or "")
        for e in ws.get("exercises") or []:
            status_raw = str(e.get("executionStatus") or "")
            if status_raw in ("Done", "DoneAsModified"):
                status = "done"
            elif status_raw == "Doing":
                status = "doing"
            elif status_raw in ("Partial", "PartiallyDone"):
                status = "partial"
            else:
                status = "todo"
            done_on = str(e.get("doneOn") or "")
            if done_on.startswith("0001-"):
                done_on = ""
            targets = _steps_to_sets(e.get("steps"))
            device = str(e.get("equipmentConnectedDevice") or "")
            st.exercises.append(
                LiveExercise(
                    position=int(e.get("position") or 0),
                    name=str(e.get("name") or e.get("shortName") or ""),
                    short_name=str(e.get("shortName") or e.get("name") or ""),
                    equipment=str(e.get("equipmentName") or ""),
                    kind=_kind(str(e.get("physicalActivityType") or ""), bool(e.get("isCardio"))),
                    status=status,
                    source=("machine" if device == "FullConnected" else ("manual" if status == "done" else "")),
                    device=device,
                    done_on=done_on,
                    sets=targets if status == "done" else [],
                    target_sets=targets,
                    done_move=int(e.get("doneMove") or 0) or None,
                    done_calories=int(e.get("doneCalories") or 0) or None,
                    picture_url=str(e.get("pictureUrl") or ((e.get("imageFrames") or [""])[0] if isinstance(e.get("imageFrames"), list) else "") or ""),
                    equipment_picture_url=str(e.get("equipmentPictureUrl") or ""),
                    muscles=[str(m.get("muscleName") or "") for m in (e.get("muscles") or []) if isinstance(m, dict) and m.get("muscleName")][:4],
                    muscle_types=[str(m.get("muscleType") or "") for m in (e.get("muscles") or []) if isinstance(m, dict) and m.get("muscleType")][:6],
                    pa_id=str(e.get("physicalActivityId") or ""),
                    rm1_kg=_rm1(e.get("currentReferenceValues")),
                )
            )
        self._fill_previous(st)
        st.exercises.sort(key=lambda x: x.position)
        st.total_count = len(st.exercises)
        st.done_count = sum(1 for e in st.exercises if e.status == "done")
        doing = next((e.position for e in st.exercises if e.status == "doing"), None)
        st.current_position = doing if doing is not None else next((e.position for e in st.exercises if e.status != "done"), None)
        return st

    def _fetch(self, workout_id: str, day: date) -> LiveState:
        st = LiveState(workout_id=workout_id, date=day.isoformat(), fetched_at=int(time.time()))
        if self._client is None:
            return st
        # 1. seance courante (ouverte sur une machine, un kiosque ou l'app) : GetCurrentWorkoutSession
        #    renvoie idCr + chaque exercice avec executionStatus / doneOn / equipmentConnectedDevice,
        #    avant meme que la seance n'apparaisse dans ActivityHistory (observe le 2026-09-30).
        try:
            cur = self._client.current_workout_session()
        except mw.MywellnessError:
            cur = {}
        ws = cur.get("workoutSession") if isinstance(cur, dict) else None
        if isinstance(ws, dict) and ws.get("exercises") and str(ws.get("workoutSessionId")) == workout_id:
            return self._from_current(ws, st)
        st.has_current_workout = bool(isinstance(cur, dict) and cur.get("hasCurrentWorkout"))
        # 2. sinon, seance performee du jour deja fermee : historique + detail
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
