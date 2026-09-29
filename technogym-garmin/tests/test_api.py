from __future__ import annotations

import os

ADMIN = {"X-Admin-Token": "admin-secret"}


def test_health(client):
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json()["mywellness_configured"] is True


def test_pair_requires_admin(client):
    assert client.post("/auth/pair").status_code == 401
    r = client.post("/auth/pair", json={"label": "montre"}, headers=ADMIN)
    assert r.status_code == 200
    assert len(r.json()["token"]) > 20


def test_workout_today_with_pair_token(client, today_in_fixtures):
    token = client.post("/auth/pair", headers=ADMIN).json()["token"]
    # sans token -> refuse (un token existe)
    assert client.get("/workout/today").status_code == 401
    r = client.get("/workout/today", params={"day": today_in_fixtures.isoformat()}, headers={"X-Pair-Token": token})
    assert r.status_code == 200
    w = r.json()
    assert set(w) >= {"id", "date", "name", "exercises"}
    assert w["date"] == today_in_fixtures.isoformat()
    first_strength = next(e for e in w["exercises"] if e["kind"] == "strength")
    assert first_strength["sets"][0] == {"reps": 10, "weight_kg": 80.0, "rest_s": 45}
    # champs None exclus pour la montre
    assert "power_w" not in first_strength["sets"][0]
    # token en query string aussi (Communications.makeWebRequest)
    assert client.get("/workout/today", params={"token": token}).status_code == 200


def test_workout_by_id_and_all(client, program_raw):
    sid = program_raw["workoutSessions"][1]["id"]
    r = client.get(f"/workout/{sid}", headers=ADMIN)
    assert r.status_code == 200
    assert r.json()["name"] == "Séance 2"
    assert client.get("/workout/does-not-exist", headers=ADMIN).status_code == 404
    assert len(client.get("/workout/all", headers=ADMIN).json()) == 3


def test_results_stored(client, program_raw, app_state):
    sid = program_raw["workoutSessions"][0]["id"]
    token = client.post("/auth/pair", headers=ADMIN).json()["token"]
    body = {
        "date": "2026-09-30",
        "device": "fr965",
        "fit_saved": True,
        "exercises": [{"position": 2, "name": "Leg press", "sets": [{"reps": 10, "weight_kg": 80}, {"reps": 8, "weight_kg": 80, "skipped": False}]}],
    }
    r = client.post(f"/workout/{sid}/results", json=body, headers={"X-Pair-Token": token})
    assert r.status_code == 200
    assert r.json()["stored"] is True
    assert r.json()["sets"] == 2
    assert r.json()["mywellness"] == "stored"
    stored = client.get(f"/workout/{sid}/results", headers=ADMIN).json()
    assert stored[0]["payload"]["exercises"][0]["sets"][1]["reps"] == 8


def test_results_writeback_flag(client, program_raw, fake_client, monkeypatch):
    monkeypatch.setenv("MYWELLNESS_WRITEBACK", "1")
    sid = program_raw["workoutSessions"][0]["id"]
    body = {"date": "2026-09-30", "exercises": [{"position": 2, "sets": [{"reps": 10, "weight_kg": 80}]}]}
    r = client.post(f"/workout/{sid}/results", json=body, headers=ADMIN)
    assert r.status_code == 200
    assert r.json()["mywellness"] == "ok"
    actions = [a for a, _ in fake_client.written]
    assert actions == ["StartWorkoutSession", "SavePerformedPhysicalActivity", "CloseWorkoutSession"]
    saved = fake_client.written[1][1]
    assert saved["summaryData"]["steps"][0]["data"][0] == {"physicalProperty": "IsoReps", "value": 10}


def test_history(client):
    r = client.get("/history", params={"days": 365, "limit": 2, "details": "true"}, headers=ADMIN)
    assert r.status_code == 200
    sessions = r.json()
    assert len(sessions) == 2
    assert sessions[0]["exercises"]
