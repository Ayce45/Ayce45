from __future__ import annotations

from datetime import date

from app.mywellness import history as hist
from app.mywellness.models import build_workout, parse_exercise
from app.mywellness.program import ProgramService


def test_parse_strength_exercise(program_raw, details_raw):
    s = program_raw["workoutSessions"][0]
    pa = details_raw[f"{s['id']}#2"]["data"]["userPhysicalActivity"]
    ex = parse_exercise(pa)
    assert ex.kind == "strength"
    assert ex.equipment == "Leg press Sel"
    assert len(ex.sets) == 4
    assert ex.sets[0].reps == 10
    assert ex.sets[0].weight_kg == 80.0
    assert ex.sets[0].rest_s == 45
    assert ex.rep_duration_s == 3


def test_parse_cardio_and_stretching(program_raw, details_raw):
    s = program_raw["workoutSessions"][0]
    cardio = parse_exercise(details_raw[f"{s['id']}#1"]["data"]["userPhysicalActivity"])
    assert cardio.kind == "cardio"
    assert cardio.sets[0].duration_s == 60
    assert cardio.sets[0].power_w == 126.0
    stretch = parse_exercise(details_raw[f"{s['id']}#9"]["data"]["userPhysicalActivity"])
    assert stretch.kind == "stretching"
    assert stretch.sets[0].duration_s == 30


def test_build_workout_shape(program_raw, details_raw):
    s = program_raw["workoutSessions"][0]
    details = [details_raw[f"{s['id']}#{pa['position']}"]["data"]["userPhysicalActivity"] for pa in s["physicalActivities"]]
    w = build_workout(s, details, "2026-09-30", program_raw)
    assert w.id == s["id"]
    assert w.date == "2026-09-30"
    assert w.name == "Séance 1"
    assert [e.position for e in w.exercises] == list(range(1, 11))
    dumped = w.model_dump(exclude_none=True)
    assert dumped["exercises"][1]["sets"][0] == {"reps": 10, "weight_kg": 80.0, "rest_s": 45}


def test_pick_session_suggested_then_cyclic(fake_client, today_in_fixtures):
    svc = ProgramService(fake_client, cache_ttl=0)
    # statut Suggested present dans la fixture -> seance 1
    picked = svc.pick_session(today_in_fixtures)
    assert picked["position"] == 1
    # sans statut Suggested : cyclique apres la derniere seance performee (seance 3 -> seance 1)
    for s in svc.program()["workoutSessions"]:
        s["workoutSessionStatus"] = "None"
    svc._history_ts = 0
    picked = svc.pick_session(today_in_fixtures)
    assert picked["position"] == 1


def test_pick_session_same_day_keeps_performed(fake_client, history_raw):
    svc = ProgramService(fake_client, cache_ttl=0)
    last = [i for i in history_raw if i.get("type") == "WorkoutSession"][0]
    d = str(last["partitionDate"])
    day = date(int(d[:4]), int(d[4:6]), int(d[6:8]))
    picked = svc.pick_session(day)
    assert picked["id"] == last["userWorkoutSessionId"]


def test_today_workout_uses_details(fake_client, today_in_fixtures):
    svc = ProgramService(fake_client, cache_ttl=0)
    w = svc.today(today_in_fixtures)
    assert w.exercises[1].sets[0].weight_kg == 80.0
    assert fake_client.calls.count("GetUserWorkoutSessionPhysicalActivity") == 10


def test_history_parsing(history_raw, performed_raw):
    summaries = [hist.parse_summary(i) for i in history_raw if i.get("type") == "WorkoutSession"]
    assert summaries[0].date.count("-") == 2
    sess = hist.parse_performed_session(performed_raw, summaries[0])
    assert sess.exercises is not None
    done = [e for e in sess.exercises if e.status == "Done" and e.kind == "strength"][0]
    assert done.sets[0].reps == 15
    assert done.sets[0].weight_kg == 40.0
    assert done.prescribed_sets[0].rest_s == 30
