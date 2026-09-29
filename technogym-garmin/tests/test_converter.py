from __future__ import annotations

import json

from app.garmin.converter import catalog_has, load_map, map_exercise, to_garmin_workout
from app.mywellness.models import Exercise, SetTarget, Workout, build_workout


def _workout(program_raw, details_raw, idx=0):
    s = program_raw["workoutSessions"][idx]
    details = [details_raw[f"{s['id']}#{pa['position']}"]["data"]["userPhysicalActivity"] for pa in s["physicalActivities"]]
    return build_workout(s, details, "2026-09-30", program_raw)


def test_map_entries_exist_in_catalog():
    m = load_map()
    for section in ("by_equipment_and_name", "by_equipment", "by_name", "by_type"):
        for key, entry in m[section].items():
            assert catalog_has(entry["category"], entry.get("exercise")), f"{section}:{key} -> {entry}"
    assert catalog_has(m["fallback"]["category"], m["fallback"].get("exercise"))


def test_map_real_program_exercises(program_raw, details_raw):
    for idx in range(3):
        w = _workout(program_raw, details_raw, idx)
        for ex in w.exercises:
            cat, exo, method = map_exercise(ex)
            assert method != "fallback", f"{ex.name} / {ex.equipment} sans mapping"
            assert catalog_has(cat, exo)


def test_fallback_for_unknown_exercise():
    ex = Exercise(position=1, name="Machine inconnue", equipment="Zorglub", sets=[SetTarget(reps=8)])
    cat, exo, method = map_exercise(ex)
    assert method == "fallback"
    assert cat == "TOTAL_BODY"


def test_convert_uses_repeat_groups_and_rest(program_raw, details_raw):
    w = _workout(program_raw, details_raw, 0)
    payload, report = to_garmin_workout(w)
    assert payload["sportType"]["sportTypeKey"] == "strength_training"
    steps = payload["workoutSegments"][0]["workoutSteps"]
    assert len(report) == len(w.exercises)
    # Leg press : 4 series identiques -> RepeatGroupDTO x4 avec exercice + repos
    leg = next(s for s in steps if s["type"] == "RepeatGroupDTO" and s["workoutSteps"][0]["exerciseName"] == "LEG_PRESS")
    assert leg["numberOfIterations"] == 4
    assert leg["workoutSteps"][0]["endCondition"]["conditionTypeKey"] == "reps"
    assert leg["workoutSteps"][0]["endConditionValue"] == 10.0
    assert leg["workoutSteps"][0]["weightValue"] == 80.0
    assert leg["workoutSteps"][1]["stepType"]["stepTypeKey"] == "rest"
    assert leg["workoutSteps"][1]["endConditionValue"] == 45.0
    # Leg curl : derniere serie differente -> steps a plat
    flat = [s for s in steps if s["type"] == "ExecutableStepDTO" and s.get("exerciseName") == "LEG_CURL"]
    assert len(flat) == 4
    assert flat[-1]["weightValue"] == 52.5
    # ordre des steps continu
    orders = [s["stepOrder"] for s in steps]
    assert orders == list(range(1, len(steps) + 1))
    json.dumps(payload)  # serialisable


def test_convert_cardio_as_time_steps():
    w = Workout(id="x", date="2026-09-30", name="Test", exercises=[
        Exercise(position=1, name="Bike: Exercice", equipment="Bike", kind="cardio",
                 sets=[SetTarget(duration_s=180, power_w=86), SetTarget(duration_s=180, power_w=102)]),
    ])
    payload, _ = to_garmin_workout(w)
    steps = payload["workoutSegments"][0]["workoutSteps"]
    assert len(steps) == 2
    assert steps[0]["endCondition"]["conditionTypeKey"] == "time"
    assert steps[0]["category"] == "INDOOR_BIKE"
    assert "86 W" in steps[0]["description"]
