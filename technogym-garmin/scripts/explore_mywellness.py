#!/usr/bin/env python
"""Reconnaissance de l'API privee Mywellness.

Execute avec les identifiants du .env :
  1. login (core.mywellness.com) et salles du compte
  2. programme prescrit (GetUserTrainingProgram) et, pour chaque exercice,
     les series prescrites (GetUserWorkoutSessionPhysicalActivity)
  3. historique (ActivityHistory) et derniere seance performee
  4. signature des actions d'ecriture (appel a vide, on lit les messages d'erreur)
  5. fixtures anonymisees dans tests/fixtures/ (option --write-fixtures)

Sortie humaine sur stdout, sans aucun identifiant ni jeton.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from datetime import date, timedelta
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from app.config import get_settings  # noqa: E402
from app.mywellness import client as mw  # noqa: E402

FIXTURES = ROOT / "tests" / "fixtures"

WRITE_ACTIONS = [
    mw.START_WORKOUT_SESSION,
    mw.CLOSE_WORKOUT_SESSION,
    mw.SAVE_PERFORMED_PA,
    mw.MARK_PA_DONE,
    mw.DELETE_PERFORMED_PA,
    "SaveUserPhysicalActivity",
    "UpdateUserWorkoutSessionPhysicalActivity",
    "ReplaceUserWorkoutSessionPhysicalActivity",
    "DeleteUserWorkoutSessionPhysicalActivity",
    "SaveUserTrainingProgram",
    "SaveGoal",
]

SENSITIVE_KEYS = {
    "token", "email", "accountUsername", "firstName", "lastName", "nickName", "birthDate",
    "displayBirthDate", "pictureUrl", "thumbPictureUrl", "address", "credentialId",
    "lastUpdateBy", "planAuthor",
}
UUID_RE = re.compile(r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}", re.I)


NAME_REPLACEMENTS: dict[str, str] = {}


def anonymize(obj: Any, uuid_map: dict[str, str]) -> Any:
    """Remplace les cles sensibles, les noms connus et renumerote les UUID de facon stable."""
    if isinstance(obj, dict):
        out = {}
        for k, v in obj.items():
            key = anonymize(k, uuid_map) if isinstance(k, str) else k
            if k in SENSITIVE_KEYS:
                out[key] = "<redacted>"
            else:
                out[key] = anonymize(v, uuid_map)
        return out
    if isinstance(obj, list):
        return [anonymize(x, uuid_map) for x in obj]
    if isinstance(obj, str):
        def repl(m: re.Match[str]) -> str:
            key = m.group(0).lower()
            if key not in uuid_map:
                n = len(uuid_map) + 1
                uuid_map[key] = f"00000000-0000-4000-8000-{n:012d}"
            return uuid_map[key]
        out = UUID_RE.sub(repl, obj)
        for old, new in NAME_REPLACEMENTS.items():
            if old:
                out = re.sub(re.escape(old), new, out, flags=re.I)
        return out
    return obj


def steps_of(pa: dict[str, Any]) -> list[dict[str, Any]]:
    pres = pa.get("displayPrescibedPhysicalActivity") or {}
    return [{p["physicalProperty"]: p.get("value") for p in st.get("properties", [])} for st in pres.get("steps", [])]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--write-fixtures", action="store_true", help="ecrit des fixtures anonymisees dans tests/fixtures")
    ap.add_argument("--days", type=int, default=90)
    args = ap.parse_args()

    s = get_settings()
    c = mw.MywellnessClient(s.mywellness_email, s.mywellness_password)
    uuid_map: dict[str, str] = {}
    fixtures: dict[str, Any] = {}

    print("== 1. Login")
    user = c.login()
    NAME_REPLACEMENTS[user.first_name] = "Utilisateur"
    print(f"   utilisateur ok, culture={user.culture}, unites={user.measurement_system}, salles={len(user.facilities)}")
    for f in user.facilities:
        print(f"   - {f.name} (url={f.url})")

    print("\n== 2. Programme prescrit (GetUserTrainingProgram)")
    prog = c.user_training_program_raw()
    for key in ("planAuthor", "lastUpdateBy"):
        if prog.get(key):
            NAME_REPLACEMENTS[str(prog[key])] = "Coach"
    fixtures["GetUserTrainingProgram"] = {"data": {"userTrainingProgramDetails": prog}}
    print(f"   {prog.get('name')!r} assigne le {prog.get('assignedOn')} expire le {prog.get('expiresOn')}")
    print(f"   rotation={prog.get('workoutRotationMode', {}).get('workoutRotationModeType')} cible/semaine={prog.get('targetWorkouts')}")
    sessions = prog.get("workoutSessions") or []
    fixtures["GetUserWorkoutSessionPhysicalActivity"] = {}
    for ws in sessions:
        print(f"   [{ws.get('position')}] {ws.get('name')} status={ws.get('workoutSessionStatus')} exercices={ws.get('physicalActivitiesCounter')} duree={ws.get('displayDurationShort')}")
        for pa in ws.get("physicalActivities") or []:
            detail = c.user_workout_session_physical_activity_raw(ws["id"], pa["position"])
            fixtures["GetUserWorkoutSessionPhysicalActivity"][f"{ws['id']}#{pa['position']}"] = {"data": {"userPhysicalActivity": detail}}
            steps = steps_of(detail)
            compact = "; ".join(
                ",".join(f"{k}={v:g}" for k, v in st.items()) for st in steps[:4]
            ) + (f" ... ({len(steps)} etapes)" if len(steps) > 4 else "")
            print(f"       {pa['position']:>2}. {detail.get('physicalActivityName')} [{detail.get('physicalActivityType')}] -> {compact}")

    print("\n== 3. Historique (ActivityHistory)")
    today = date.today()
    items = c.activity_history(today - timedelta(days=args.days), today, only_workouts=False)
    fixtures["ActivityHistory"] = {"data": {"items": items}}
    kinds: dict[str, int] = {}
    for it in items:
        kinds[str(it.get("type"))] = kinds.get(str(it.get("type")), 0) + 1
    print(f"   {len(items)} elements sur {args.days} jours: {kinds}")
    workouts = [i for i in items if i.get("type") == "WorkoutSession"]
    for it in workouts[:5]:
        print(f"   - {mw.partition_to_iso(it.get('partitionDate'))} {it.get('name')} idCr={it.get('idCr')} exos={it.get('numberOfExerciseDoneWithGroups')}/{it.get('numberOfExerciseToDoWithGroups')}")
    if workouts:
        last = workouts[0]
        sess = c.performed_session_raw(last["idCr"], str(last["partitionDate"]), last.get("facilityId"))
        fixtures["GetPerformedWorkoutSessionByIdCr"] = {"data": sess}
        print(f"\n   Derniere seance performee: {sess.get('name')} debut={sess.get('startedOn')} efficacite={sess.get('workoutEfficacy')}")
        for a in sess.get("physicalActivities") or []:
            perf = a.get("performedPhysicalActivity") or {}
            done = [{p["physicalProperty"]: p.get("value") for p in st.get("data", [])} for st in (perf.get("data") or {}).get("steps") or []]
            print(f"     - {a.get('physicalActivityName')} status={a.get('status')} prescrit={steps_of(a)[:2]} fait={done[:2]}")

    print("\n== 4. Etat courant et signatures des actions d'ecriture (appels a vide)")
    print(f"   GetCurrentWorkoutSession -> {c.current_workout_session()}")
    for action in WRITE_ACTIONS:
        try:
            res = c.post_action(action, {})
            print(f"   {action}: OK (reponse {json.dumps(res)[:120]})")
        except mw.NotFoundError:
            print(f"   {action}: 404 (n'existe pas)")
        except mw.MywellnessError as exc:
            print(f"   {action}: {exc}")

    if args.write_fixtures:
        FIXTURES.mkdir(parents=True, exist_ok=True)
        for name, payload in fixtures.items():
            path = FIXTURES / f"{name}.json"
            path.write_text(json.dumps(anonymize(payload, uuid_map), indent=1, ensure_ascii=False), encoding="utf-8")
            print(f"   fixture ecrite: {path.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
