"""Conversion d'une seance simplifiee en workout structure Garmin Connect (sport Strength).

Structure produite (workout-service) :
  workout
    workoutSegments[0].workoutSteps[]
      ExecutableStepDTO stepType interval + endCondition reps/time + category/exerciseName + weightValue
      ExecutableStepDTO stepType rest + endCondition time
      RepeatGroupDTO numberOfIterations + workoutSteps[exercice, repos] quand toutes les series sont identiques
"""

from __future__ import annotations

import json
import re
import unicodedata
from functools import lru_cache
from pathlib import Path
from typing import Any

from app.mywellness.models import Exercise, SetTarget, Workout

HERE = Path(__file__).resolve().parent
MAP_PATH = HERE / "exercise_map.json"
CATALOG_PATH = HERE / "garmin_exercises.json"

SPORT_STRENGTH = {"sportTypeId": 5, "sportTypeKey": "strength_training", "displayOrder": 5}
STEP_INTERVAL = {"stepTypeId": 3, "stepTypeKey": "interval", "displayOrder": 3}
STEP_REST = {"stepTypeId": 5, "stepTypeKey": "rest", "displayOrder": 5}
STEP_REPEAT = {"stepTypeId": 6, "stepTypeKey": "repeat", "displayOrder": 6}
COND_TIME = {"conditionTypeId": 2, "conditionTypeKey": "time", "displayOrder": 2, "displayable": True}
COND_REPS = {"conditionTypeId": 10, "conditionTypeKey": "reps", "displayOrder": 10, "displayable": True}
COND_ITER = {"conditionTypeId": 7, "conditionTypeKey": "iterations", "displayOrder": 7, "displayable": False}
COND_LAP = {"conditionTypeId": 1, "conditionTypeKey": "lap.button", "displayOrder": 1, "displayable": True}
TARGET_NONE = {"workoutTargetTypeId": 1, "workoutTargetTypeKey": "no.target", "displayOrder": 1}
UNIT_KG = {"unitId": 8, "unitKey": "kilogram", "factor": 1000.0}

DEFAULT_REP_DURATION_S = 3
DEFAULT_REST_S = 60


def normalize(s: str) -> str:
    s = unicodedata.normalize("NFKD", s or "")
    s = "".join(ch for ch in s if not unicodedata.combining(ch))
    s = s.replace("–", "-").replace("—", "-").replace("’", "'")
    s = re.sub(r"\s+", " ", s).strip().lower()
    return s


@lru_cache
def load_map() -> dict[str, Any]:
    return json.loads(MAP_PATH.read_text(encoding="utf-8"))


@lru_cache
def load_catalog() -> dict[str, set[str]]:
    data = json.loads(CATALOG_PATH.read_text(encoding="utf-8"))
    return {cat: set((v.get("exercises") or {}).keys()) for cat, v in (data.get("categories") or {}).items()}


def catalog_has(category: str, exercise: str | None) -> bool:
    cat = load_catalog()
    if category not in cat:
        return False
    return exercise is None or exercise in cat[category]


def map_exercise(ex: Exercise) -> tuple[str, str | None, str]:
    """Retourne (category, exerciseName | None, methode)."""
    m = load_map()
    eq = normalize(ex.equipment)
    names = [normalize(n) for n in (ex.short_name, ex.name) if n]
    # le nom complet est souvent "Machine: mouvement"
    names += [normalize(n.split(":", 1)[1]) for n in (ex.name,) if ":" in n]

    def ok(entry: dict[str, Any] | None) -> tuple[str, str | None] | None:
        if not entry:
            return None
        cat, exo = entry.get("category"), entry.get("exercise")
        if catalog_has(cat, exo):
            return cat, exo
        if catalog_has(cat, None):
            return cat, None
        return None

    for n in names:
        r = ok(m.get("by_equipment_and_name", {}).get(f"{eq}|{n}"))
        if r:
            return r[0], r[1], "equipment+name"
    r = ok(m.get("by_equipment", {}).get(eq))
    if r:
        return r[0], r[1], "equipment"
    for n in names:
        r = ok(m.get("by_name", {}).get(n))
        if r:
            return r[0], r[1], "name"
    r = ok(m.get("by_type", {}).get(ex.kind))
    if r:
        return r[0], r[1], "type"
    fb = m.get("fallback") or {"category": "TOTAL_BODY", "exercise": None}
    return fb["category"], fb.get("exercise"), "fallback"


def _exercise_step(ex: Exercise, s: SetTarget, order: int, category: str, exercise: str | None, label: str) -> dict[str, Any]:
    step: dict[str, Any] = {
        "type": "ExecutableStepDTO",
        "stepOrder": order,
        "stepType": dict(STEP_INTERVAL),
        "childStepId": None,
        "description": label,
        "targetType": dict(TARGET_NONE),
        "category": category,
        "exerciseName": exercise,
    }
    if ex.kind == "strength" and s.reps:
        step["endCondition"] = dict(COND_REPS)
        step["endConditionValue"] = float(s.reps)
        if s.weight_kg:
            step["weightValue"] = float(s.weight_kg)
            step["weightUnit"] = dict(UNIT_KG)
    elif s.duration_s:
        step["endCondition"] = dict(COND_TIME)
        step["endConditionValue"] = float(s.duration_s)
    elif s.reps:
        step["endCondition"] = dict(COND_REPS)
        step["endConditionValue"] = float(s.reps)
    else:
        step["endCondition"] = dict(COND_LAP)
        step["endConditionValue"] = None
    return step


def _rest_step(order: int, rest_s: int) -> dict[str, Any]:
    return {
        "type": "ExecutableStepDTO",
        "stepOrder": order,
        "stepType": dict(STEP_REST),
        "childStepId": None,
        "description": None,
        "endCondition": dict(COND_TIME),
        "endConditionValue": float(rest_s),
        "targetType": dict(TARGET_NONE),
    }


def _set_label(ex: Exercise, s: SetTarget, idx: int, total: int) -> str:
    base = ex.short_name or ex.name
    parts = [f"{base} {idx}/{total}"]
    if s.weight_kg:
        parts.append(f"{s.weight_kg:g} kg")
    if s.power_w:
        parts.append(f"{s.power_w:g} W")
    if s.level:
        parts.append(f"niveau {s.level:g}")
    if ex.equipment and ex.equipment.lower() not in base.lower():
        parts.append(f"({ex.equipment})")
    return " ".join(parts)[:200]


def _all_same(sets: list[SetTarget]) -> bool:
    return len(sets) > 1 and all(s.model_dump() == sets[0].model_dump() for s in sets)


def estimate_duration_s(ex: Exercise) -> int:
    total = 0
    rep_d = ex.rep_duration_s or DEFAULT_REP_DURATION_S
    for s in ex.sets:
        if s.duration_s:
            total += s.duration_s
        elif s.reps:
            total += s.reps * rep_d
        total += s.rest_s or 0
    return total


def to_garmin_workout(workout: Workout, name: str | None = None) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    """Retourne (payload workout Garmin, rapport de mapping par exercice)."""
    steps: list[dict[str, Any]] = []
    report: list[dict[str, Any]] = []
    order = 1
    for ex in workout.exercises:
        category, exercise, method = map_exercise(ex)
        report.append({"position": ex.position, "name": ex.name, "equipment": ex.equipment, "category": category, "exercise": exercise, "method": method})
        sets = ex.sets or [SetTarget()]
        total = len(sets)
        use_repeat = _all_same(sets) and (sets[0].reps or sets[0].duration_s)
        if use_repeat:
            s = sets[0]
            children = [_exercise_step(ex, s, 1, category, exercise, _set_label(ex, s, 1, total).replace(" 1/", " x/"))]
            rest = s.rest_s if s.rest_s and s.rest_s > 1 else (DEFAULT_REST_S if ex.kind == "strength" else 0)
            if rest:
                children.append(_rest_step(2, rest))
            steps.append(
                {
                    "type": "RepeatGroupDTO",
                    "stepOrder": order,
                    "stepType": dict(STEP_REPEAT),
                    "childStepId": 1,
                    "numberOfIterations": total,
                    "smartRepeat": False,
                    "endCondition": dict(COND_ITER),
                    "endConditionValue": float(total),
                    "workoutSteps": children,
                }
            )
            order += 1
            continue
        for i, s in enumerate(sets, start=1):
            steps.append(_exercise_step(ex, s, order, category, exercise, _set_label(ex, s, i, total)))
            order += 1
            rest = s.rest_s if s.rest_s and s.rest_s > 1 else (DEFAULT_REST_S if ex.kind == "strength" else 0)
            if rest and i < total:
                steps.append(_rest_step(order, rest))
                order += 1
    est = sum(estimate_duration_s(e) for e in workout.exercises) or (workout.estimated_duration_min or 45) * 60
    title = name or f"{workout.name} ({workout.date})"
    payload = {
        "sportType": dict(SPORT_STRENGTH),
        "subSportType": None,
        "workoutName": title[:80],
        "description": (f"{workout.program_name} : {workout.name}. Genere depuis Mywellness le {workout.date}.")[:1024],
        "estimatedDurationInSecs": int(est),
        "estimatedDistanceInMeters": None,
        "workoutSegments": [
            {
                "segmentOrder": 1,
                "sportType": dict(SPORT_STRENGTH),
                "workoutSteps": steps,
            }
        ],
    }
    return payload, report
