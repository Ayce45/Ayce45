#!/usr/bin/env python
"""Test en conditions reelles de l'ecriture vers Mywellness, a lancer soi-meme.

Ecrit UNE serie identifiable (1 rep, 5 kg par defaut) sur un exercice "ToDo" d'une seance performee du jour
choisi, relit la seance, puis tente la suppression (DeletePerformedPhysicalActivity). Affiche tout.

  python scripts/test_writeback.py --list                       # seances performees recentes
  python scripts/test_writeback.py --idcr 1146 --day 2026-09-29 --position 3
  python scripts/test_writeback.py --idcr 1146 --day 2026-09-29 --position 3 --reps 10 --weight 80 --no-delete

Cela cree une vraie entree dans votre historique Mywellness : verifiez ensuite dans l'app.
"""

from __future__ import annotations

import argparse
import json
import sys
from datetime import date, timedelta
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from app.config import get_settings  # noqa: E402
from app.mywellness import client as mw  # noqa: E402


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--idcr", type=int)
    ap.add_argument("--day", help="YYYY-MM-DD")
    ap.add_argument("--position", type=int)
    ap.add_argument("--reps", type=int, default=1)
    ap.add_argument("--weight", type=float, default=5.0)
    ap.add_argument("--no-delete", action="store_true")
    args = ap.parse_args()
    s = get_settings()
    c = mw.MywellnessClient(s.mywellness_email, s.mywellness_password)
    c.login()
    if args.list or not (args.idcr and args.day and args.position):
        for i in c.activity_history(date.today() - timedelta(days=60), date.today()):
            print(f"idCr={i.get('idCr')} day={i.get('partitionDate')} {i.get('name')} done={i.get('numberOfExerciseDoneWithGroups')}/{i.get('numberOfExerciseToDoWithGroups')} facility={i.get('facilityId')}")
        return 0
    partition = args.day.replace("-", "")
    hist = {str(i.get("idCr")): i for i in c.activity_history(date.today() - timedelta(days=400), date.today())}
    item = hist.get(str(args.idcr))
    fac_id = item.get("facilityId") if item else None
    raw = c.performed_session_raw(args.idcr, partition, fac_id)
    act = next((a for a in raw["physicalActivities"] if int(a.get("position") or 0) == args.position), None)
    if act is None:
        print("position introuvable")
        return 1
    print(f"Exercice: {act['physicalActivityName']} status={act['status']}")
    payload = {
        "idCr": args.idcr, "partitionDate": partition, "position": args.position,
        "physicalActivityId": act["physicalActivityId"], "userWorkoutSessionId": raw.get("userWorkoutSessionId"),
        "manuallyDone": True,
        "summaryData": {"steps": [{"data": [{"physicalProperty": "IsoReps", "value": args.reps}, {"physicalProperty": "IsoWeight", "value": args.weight}]}], "data": []},
    }
    print("SavePerformedPhysicalActivity ->", json.dumps(c.save_performed_physical_activity(payload, fac_id), ensure_ascii=False)[:500])
    raw2 = c.performed_session_raw(args.idcr, partition, fac_id)
    act2 = next(a for a in raw2["physicalActivities"] if int(a.get("position") or 0) == args.position)
    pa = act2.get("performedPhysicalActivity") or {}
    steps = [{x["physicalProperty"]: x["value"] for x in st.get("data", [])} for st in ((pa.get("data") or {}).get("steps") or [])]
    print(f"Relecture: status={act2['status']} performedId={pa.get('id')} manual={pa.get('manuallyDone')} steps={steps}")
    if args.no_delete or not pa.get("id"):
        return 0
    for body in (
        {"performedPhysicalActivityId": pa["id"], "idCr": args.idcr, "partitionDate": partition},
        {"id": pa["id"], "idCr": args.idcr, "partitionDate": partition, "position": args.position},
        {"performedPhysicalActivityId": pa["id"], "partitionDate": partition, "position": args.position, "userWorkoutSessionId": raw.get("userWorkoutSessionId")},
    ):
        try:
            print("DeletePerformedPhysicalActivity", json.dumps(body), "->", c.post_action(mw.DELETE_PERFORMED_PA, body, facility_url=c.facility_url_for_id(fac_id)))
            break
        except mw.MywellnessError as exc:
            print("DeletePerformedPhysicalActivity", json.dumps(body), "->", exc)
    raw3 = c.performed_session_raw(args.idcr, partition, fac_id)
    act3 = next(a for a in raw3["physicalActivities"] if int(a.get("position") or 0) == args.position)
    print(f"Apres suppression: status={act3['status']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
