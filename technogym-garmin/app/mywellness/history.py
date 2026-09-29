"""Historique Mywellness au format simplifie (repris de technogym_mcp, reduit a l'essentiel)."""

from __future__ import annotations

from datetime import date, timedelta
from typing import Any

from pydantic import BaseModel, Field

from app.mywellness import client as mw
from app.mywellness.models import SetTarget, kind_of, parse_prescribed_steps, partition_iso


class HistorySet(BaseModel):
    set_number: int
    reps: int | None = None
    weight_kg: float | None = None
    rest_s: int | None = None
    duration_s: int | None = None


class HistoryExercise(BaseModel):
    position: int | None = None
    name: str
    equipment: str = ""
    kind: str = "strength"
    status: str = ""
    done_on: str = ""
    sets: list[HistorySet] = Field(default_factory=list)
    prescribed_sets: list[SetTarget] = Field(default_factory=list)


class HistorySession(BaseModel):
    session_id: str
    date: str
    time: str = ""
    name: str
    type: str = ""
    duration_min: int | None = None
    calories: int | None = None
    moves: int | None = None
    exercises_done: int | None = None
    exercises_planned: int | None = None
    user_workout_session_id: str = ""
    facility_id: str = ""
    efficacy: int | None = None
    exercises: list[HistoryExercise] | None = None


def parse_summary(i: dict[str, Any]) -> HistorySession:
    def _int(v: Any) -> int | None:
        try:
            return int(float(v)) if v not in (None, "") else None
        except (TypeError, ValueError):
            return None

    return HistorySession(
        session_id=str(i.get("idCr", "")),
        date=partition_iso(i.get("partitionDate")),
        time=f"{int(i.get('hour') or 0):02d}:{int(i.get('minute') or 0):02d}",
        name=str(i.get("name", "")),
        type=str(i.get("type", "")),
        duration_min=_int(i.get("totalDurationInMinutes", i.get("duration"))),
        calories=_int(i.get("calories")),
        moves=_int(i.get("moves")),
        exercises_done=_int(i.get("numberOfExerciseDoneWithGroups")),
        exercises_planned=_int(i.get("numberOfExerciseToDoWithGroups")),
        user_workout_session_id=str(i.get("userWorkoutSessionId") or ""),
        facility_id=str(i.get("facilityId") or ""),
        efficacy=_int(i.get("workoutEffectiveness")),
    )


def _step_values(rows: list[dict[str, Any]] | None) -> dict[str, float]:
    out: dict[str, float] = {}
    for p in rows or []:
        k = p.get("physicalProperty")
        try:
            if k:
                out[str(k)] = float(p.get("value"))
        except (TypeError, ValueError):
            pass
    return out


def parse_performed_exercise(act: dict[str, Any]) -> HistoryExercise:
    pa = act.get("performedPhysicalActivity") or {}
    steps = ((pa.get("data") or {}).get("steps")) or []
    sets = []
    for n, st in enumerate(steps, start=1):
        v = _step_values(st.get("data"))
        sets.append(
            HistorySet(
                set_number=n,
                reps=int(v["IsoReps"]) if "IsoReps" in v else (int(v["Reps"]) if "Reps" in v else None),
                weight_kg=v.get("IsoWeight", v.get("Weight")),
                rest_s=int(v["RestTime"]) if "RestTime" in v else None,
                duration_s=int(v["Duration"]) if "Duration" in v else None,
            )
        )
    return HistoryExercise(
        position=act.get("position"),
        name=str(act.get("physicalActivityName") or ""),
        equipment=str(act.get("equipmentName") or ""),
        kind=kind_of(str(act.get("physicalActivityType") or ""), bool(act.get("isCardio"))),
        status=str(act.get("status") or ""),
        done_on=str(pa.get("doneOn") or ""),
        sets=sets,
        prescribed_sets=parse_prescribed_steps(act.get("displayPrescibedPhysicalActivity")),
    )


def parse_performed_session(data: dict[str, Any], summary: HistorySession | None = None) -> HistorySession:
    started = str(data.get("startedOn", ""))
    base = summary or HistorySession(session_id=str(data.get("idCr", "")), date=started[:10], name=str(data.get("name") or ""))
    base = base.model_copy(
        update={
            "name": str(data.get("displayName") or data.get("name") or base.name),
            "type": str(data.get("sessionType") or base.type),
            "efficacy": data.get("workoutEfficacy", base.efficacy),
            "user_workout_session_id": str(data.get("userWorkoutSessionId") or base.user_workout_session_id),
            "exercises": [parse_performed_exercise(a) for a in data.get("physicalActivities") or []],
        }
    )
    return base


def list_history(client: mw.MywellnessClient, days: int = 30, only_workouts: bool = True) -> list[HistorySession]:
    today = date.today()
    return [parse_summary(i) for i in client.activity_history(today - timedelta(days=days), today, only_workouts)]


def get_session(client: mw.MywellnessClient, summary: HistorySession) -> HistorySession:
    raw = client.performed_session_raw(summary.session_id, summary.date, summary.facility_id or None)
    return parse_performed_session(raw, summary)
