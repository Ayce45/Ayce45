from __future__ import annotations

from datetime import date

from app.mywellness.live import LiveService

ADMIN = {"X-Admin-Token": "admin-secret"}


def _performed_day(performed_raw) -> date:
    return date.fromisoformat(str(performed_raw["startedOn"])[:10])


def test_live_state_from_machines(fake_client, performed_raw):
    svc = LiveService(fake_client, ttl=0)
    day = _performed_day(performed_raw)
    st = svc.state(performed_raw["userWorkoutSessionId"], day)
    assert st.session_found is True
    assert st.total_count == 6
    assert st.done_count == 5
    by_pos = {e.position: e for e in st.exercises}
    assert by_pos[3].status == "todo"
    assert by_pos[4].status == "done" and by_pos[4].source == "machine"
    assert by_pos[4].sets[0].reps == 15 and by_pos[4].sets[0].weight_kg == 40.0
    assert by_pos[5].source == "manual"
    # les blocs cardio sans donnees de serie ne remontent pas de series vides
    assert by_pos[1].sets == []


def test_live_state_no_session_today(fake_client, performed_raw):
    svc = LiveService(fake_client, ttl=0)
    st = svc.state(performed_raw["userWorkoutSessionId"], date(2030, 1, 1))
    assert st.session_found is False
    assert st.exercises == []


def test_live_endpoint(client, performed_raw):
    day = _performed_day(performed_raw).isoformat()
    r = client.get(f"/workout/{performed_raw['userWorkoutSessionId']}/live", params={"day": day}, headers=ADMIN)
    assert r.status_code == 200
    body = r.json()
    assert body["session_found"] is True
    assert body["done_count"] == 5
    # champs nuls omis pour la montre
    assert all("reps" not in s or s["reps"] is not None for e in body["exercises"] for s in e["sets"])


def test_ui_page_served_without_env_credentials(client):
    r = client.get("/")
    assert r.status_code == 200
    assert "Synchroniser vers Garmin" in r.text
    assert "mw_password" in r.text
    # aucun identifiant du .env de test n'est pre-rempli dans la page
    assert "x@example.com" not in r.text


def test_ui_sync_rejects_bad_mywellness_credentials(client, monkeypatch):
    from app.api import ui as ui_mod
    from app.mywellness import client as mw

    class Refusing(mw.MywellnessClient):
        def login(self):  # type: ignore[override]
            raise mw.LoginError("Login refuse: WrongCredentials")

    monkeypatch.setattr(ui_mod.mw, "MywellnessClient", Refusing)
    monkeypatch.setattr(ui_mod, "GarminClient", lambda *a, **k: object())
    r = client.post("/ui/sync", data={"mw_email": "a@b.c", "mw_password": "bad", "g_email": "g@b.c", "g_password": "x"})
    assert r.status_code == 200
    assert r.json()["ok"] is False
    assert "Mywellness" in r.json()["error"]
