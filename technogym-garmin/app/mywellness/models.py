"""Modele simplifie d'une seance, partage entre l'API, la conversion Garmin et la montre.

Format expose par GET /workout/today :

    { "id": "...", "date": "2026-09-30", "name": "...",
      "exercises": [ { "name": "...", "sets": [ { "reps": 10, "weight_kg": 40, "rest_s": 90 } ] } ] }

Les champs supplementaires (kind, equipment, duration_s, power_w, level) sont optionnels et ignores
par les clients qui ne les connaissent pas.
"""

from __future__ import annotations

from typing import Any, Literal

from pydantic import BaseModel, Field

ExerciseKind = Literal["strength", "cardio", "stretching", "other"]


class SetTarget(BaseModel):
    reps: int | None = None
    weight_kg: float | None = None
    rest_s: int | None = None
    duration_s: int | None = None
    power_w: float | None = None
    level: float | None = None


class Exercise(BaseModel):
    position: int
    name: str
    short_name: str = ""
    equipment: str = ""
    kind: ExerciseKind = "strength"
    physical_activity_id: str = ""
    mywellness_type: str = ""
    muscles: list[str] = Field(default_factory=list)
    rep_duration_s: int | None = None
    sets: list[SetTarget] = Field(default_factory=list)


class Workout(BaseModel):
    id: str
    date: str
    name: str
    program_name: str = ""
    program_id: str = ""
    position: int | None = None
    estimated_duration_min: int | None = None
    exercises: list[Exercise] = Field(default_factory=list)
    source: str = "mywellness"


# ------------------------------------------------------------------ parsing Mywellness


def _prop_values(rows: list[dict[str, Any]] | None) -> dict[str, float]:
    out: dict[str, float] = {}
    for p in rows or []:
        key = p.get("physicalProperty") or p.get("property")
        if not key:
            continue
        try:
            out[str(key)] = float(p.get("value"))
        except (TypeError, ValueError):
            continue
    return out


def kind_of(mw_type: str, is_cardio: bool = False) -> ExerciseKind:
    t = (mw_type or "").lower()
    if t.startswith("cardio") or is_cardio:
        return "cardio"
    if t.startswith("stretch") or t == "flexibility":
        return "stretching"
    if t.startswith("strength") or t in ("functional", "bodyweight", "isotonic"):
        return "strength"
    return "other"


def _to_int(v: float | None) -> int | None:
    return int(round(v)) if v is not None else None


def parse_prescribed_steps(pres: dict[str, Any] | None) -> list[SetTarget]:
    """Convertit displayPrescibedPhysicalActivity.steps[] en SetTarget[]."""
    sets: list[SetTarget] = []
    for st in (pres or {}).get("steps") or []:
        v = _prop_values(st.get("properties") or st.get("data"))
        reps = v.get("IsoReps", v.get("Reps"))
        weight = v.get("IsoWeight", v.get("Weight"))
        rest = v.get("RestTime")
        duration = v.get("Duration")
        sets.append(
            SetTarget(
                reps=_to_int(reps),
                weight_kg=weight,
                rest_s=_to_int(rest),
                duration_s=_to_int(duration),
                power_w=v.get("Power"),
                level=v.get("Level"),
            )
        )
    return sets


def parse_exercise(pa: dict[str, Any]) -> Exercise:
    """Exercice depuis GetUserWorkoutSessionPhysicalActivity (ou une entree de programme)."""
    pres = pa.get("displayPrescibedPhysicalActivity") or {}
    ext = pres.get("extData") or {}
    rep_dur = None
    try:
        rep_dur = int(float(ext.get("mwc_default_rep_duration"))) if ext.get("mwc_default_rep_duration") else None
    except (TypeError, ValueError):
        rep_dur = None
    return Exercise(
        position=int(pa.get("position") or 0),
        name=str(pa.get("physicalActivityName") or pa.get("physicalActivityShortName") or "").strip(),
        short_name=str(pa.get("physicalActivityShortName") or "").strip(),
        equipment=str(pa.get("equipmentName") or "").strip(),
        kind=kind_of(str(pa.get("physicalActivityType") or ""), bool(pa.get("isCardio"))),
        physical_activity_id=str(pa.get("physicalActivityId") or ""),
        mywellness_type=str(pa.get("physicalActivityType") or ""),
        muscles=[str(m.get("muscleName") or m.get("muscleType")) for m in pa.get("muscles") or []],
        rep_duration_s=rep_dur,
        sets=parse_prescribed_steps(pres),
    )


def _duration_min(display_short: str | None, estimated_s: int | None) -> int | None:
    if estimated_s:
        return int(round(estimated_s / 60))
    if display_short:
        digits = "".join(ch for ch in display_short if ch.isdigit())
        if digits:
            return int(digits)
    return None


def build_workout(session: dict[str, Any], details: list[dict[str, Any]], day: str, program: dict[str, Any] | None = None) -> Workout:
    """Assemble une seance simplifiee a partir d'une seance de programme et de ses exercices detailles."""
    exercises = sorted((parse_exercise(d) for d in details), key=lambda e: e.position)
    return Workout(
        id=str(session.get("id") or session.get("userWorkoutSessionId") or ""),
        date=day,
        name=str(session.get("name") or session.get("displayName") or "Seance"),
        program_name=str((program or {}).get("name") or session.get("tpName") or ""),
        program_id=str((program or {}).get("id") or session.get("userTrainingProgramId") or ""),
        position=int(session["position"]) if session.get("position") is not None else None,
        estimated_duration_min=_duration_min(session.get("displayDurationShort"), None),
        exercises=exercises,
    )


# ------------------------------------------------------------------ resultats (montre -> backend)


class SetResult(BaseModel):
    reps: int | None = None
    weight_kg: float | None = None
    duration_s: int | None = None
    rest_s: int | None = None
    completed_at: str | None = None
    skipped: bool = False


class ExerciseResult(BaseModel):
    position: int
    name: str = ""
    physical_activity_id: str = ""
    sets: list[SetResult] = Field(default_factory=list)


class WorkoutResults(BaseModel):
    workout_id: str = ""
    date: str = ""
    device: str = ""
    started_at: str | None = None
    finished_at: str | None = None
    fit_saved: bool | None = None
    exercises: list[ExerciseResult] = Field(default_factory=list)


def partition_iso(p: Any) -> str:
    s = str(p or "")
    return f"{s[:4]}-{s[4:6]}-{s[6:8]}" if len(s) == 8 and s.isdigit() else s
