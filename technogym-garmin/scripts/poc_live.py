#!/usr/bin/env python
"""POC lecture live d'une seance Technogym depuis Mywellness (sans toucher aux machines).

Boucle toutes les N secondes (defaut 15) et affiche ce qui change cote cloud Technogym :
  * GetCurrentWorkoutSession        : une seance est-elle ouverte (kiosque Unity Self / app / machine) ?
  * ActivityHistory (jour)          : la seance performee du jour (idCr) apparait des l'ouverture
  * GetPerformedWorkoutSessionByIdCr: par exercice, statut ToDo/Done, heure de fin (doneOn), console
                                      d'origine (VisioWow, UnityStrength...), series reelles (reps, kg)
  * CardioLog/{analyticsId}/Details : pour un exercice cardio termine, courbes par seconde (W, rpm, m)

A lancer pendant une seance en salle :  python scripts/poc_live.py [--interval 15] [--day YYYY-MM-DD]
Il ecrit aussi un journal JSON (scratch/poc_live_log.jsonl) pour analyse a posteriori.
Rien n'est ecrit cote Mywellness : lecture seule.
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from datetime import date, datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from app.config import get_settings  # noqa: E402
from app.mywellness import client as mw  # noqa: E402
from app.mywellness.models import partition_iso  # noqa: E402

LOG = ROOT / "scratch" / "poc_live_log.jsonl"


def now() -> str:
    return datetime.now().strftime("%H:%M:%S")


def snapshot(c: mw.MywellnessClient, day: date) -> dict:
    cur = c.current_workout_session()
    try:
        cur["workout_current"] = c.current_workout()   # GET workout.mywellness.com/v2/enduser/workout/current
    except mw.MywellnessError as exc:
        cur["workout_current"] = {"error": str(exc)}
    items = c.activity_history(day, day)
    sessions = []
    for it in items:
        if partition_iso(it.get("partitionDate")) != day.isoformat() or it.get("idCr") in (None, ""):
            continue
        raw = c.performed_session_raw(it["idCr"], str(it["partitionDate"]), it.get("facilityId"))
        exs = []
        for a in raw.get("physicalActivities") or []:
            pa = a.get("performedPhysicalActivity") or {}
            steps = [{x["physicalProperty"]: x["value"] for x in st.get("data", [])} for st in ((pa.get("data") or {}).get("steps") or [])]
            exs.append({
                "position": a.get("position"), "name": a.get("physicalActivityName"), "status": a.get("status"),
                "done_on": pa.get("doneOn"), "console": (pa.get("extData") or {}).get("mwc_client_application"),
                "analytics_id": a.get("analyticsId") or pa.get("analiticsId"), "sets": steps,
            })
        sessions.append({
            "id_cr": it["idCr"], "name": raw.get("name"), "started_on": raw.get("startedOn"), "closed_on": raw.get("closedOn"),
            "status": raw.get("workoutSessionStatus"), "client": (raw.get("extData") or {}).get("mwc_client_application"),
            "done": it.get("numberOfExerciseDoneWithGroups"), "todo": it.get("numberOfExerciseToDoWithGroups"), "exercises": exs,
        })
    return {"t": now(), "current": cur, "sessions": sessions}


def diff(prev: dict | None, cur: dict) -> list[str]:
    out = []
    if prev is None:
        out.append(f"seance ouverte cote cloud: {cur['current']}")
        for s in cur["sessions"]:
            out.append(f"seance du jour idCr={s['id_cr']} {s['name']} debut={s['started_on']} fermee={s['closed_on']!r} faits={s['done']}/{s['todo']}")
            for e in s["exercises"]:
                out.append(f"   pos {e['position']} {e['name']} : {e['status']} {('fait a ' + str(e['done_on'])[11:19] + ' via ' + str(e['console'])) if e['done_on'] else ''} {e['sets'][:3] if e['sets'] else ''}")
        return out
    if prev["current"] != cur["current"]:
        out.append(f"GetCurrentWorkoutSession : {prev['current']} -> {cur['current']}")
    prev_s = {s["id_cr"]: s for s in prev["sessions"]}
    for s in cur["sessions"]:
        p = prev_s.get(s["id_cr"])
        if p is None:
            out.append(f"NOUVELLE seance performee idCr={s['id_cr']} {s['name']} (ouverte via {s['client']})")
            continue
        if p["closed_on"] != s["closed_on"]:
            out.append(f"seance idCr={s['id_cr']} fermee: {s['closed_on']}")
        pe = {e["position"]: e for e in p["exercises"]}
        for e in s["exercises"]:
            q = pe.get(e["position"])
            if q is None or q["status"] != e["status"] or q["sets"] != e["sets"]:
                out.append(f"exercice pos {e['position']} {e['name']} : {q['status'] if q else '?'} -> {e['status']} via {e['console']} series={e['sets']}")
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--interval", type=int, default=15)
    ap.add_argument("--day", default=None)
    ap.add_argument("--once", action="store_true")
    args = ap.parse_args()
    day = date.fromisoformat(args.day) if args.day else date.today()
    s = get_settings()
    c = mw.MywellnessClient(s.mywellness_email, s.mywellness_password)
    c.login()
    LOG.parent.mkdir(exist_ok=True)
    prev = None
    print(f"[{now()}] poll toutes les {args.interval}s, jour {day} (Ctrl+C pour arreter)")
    while True:
        try:
            cur = snapshot(c, day)
        except mw.MywellnessError as exc:
            print(f"[{now()}] erreur Mywellness: {exc}")
            time.sleep(args.interval)
            continue
        for line in diff(prev, cur):
            print(f"[{cur['t']}] {line}")
        with LOG.open("a", encoding="utf-8") as fh:
            fh.write(json.dumps(cur, ensure_ascii=False) + "\n")
        prev = cur
        if args.once:
            return 0
        time.sleep(args.interval)


if __name__ == "__main__":
    sys.exit(main())
