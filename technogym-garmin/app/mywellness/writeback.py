"""Retour des resultats vers Mywellness (montre -> Technogym), pour les exercices faits hors machine.

Flux :
  1. seance performee du jour deja ouverte par les machines (ActivityHistory + idCr) ; sinon
     StartWorkoutSession {userWorkoutSessionId} l'ouvre (retour : idCr, partitionDate)
  2. SavePerformedPhysicalActivity par exercice saisi sur la montre
  3. CloseWorkoutSession {idCr, partitionDate} si la montre indique la fin de seance

Format de SavePerformedPhysicalActivity (deduit des messages d'erreur du serveur, voir docs/mywellness-api.md) :
  facilityUrl, physicalActivityId (ou equipmentCode + physicalActivityCode + targetType), idCr, partitionDate,
  position, userWorkoutSessionId, manuallyDone, summaryData = GenericPhysicalActivityDataVO :
  {"steps": [{"data": [{"physicalProperty": "IsoReps", "value": 10}, {"physicalProperty": "IsoWeight", "value": 80}]}],
   "data": []}
  Un summaryData vide repond {"result": "ExerciseDataNotValid", "wasOnline": false}.

Etat verifie le 2026-09-30 sur une seance reelle ouverte depuis l'app :
  * MarkPhysicalActivityAsDone {position, userWorkoutSessionId, idCr, partitionDate} -> exercice Done avec
    les series prescrites (manuallyDone). C'est la voie utilisee ici.
  * SavePerformedPhysicalActivity (series reelles) : summaryData.stepData est obligatoire et les proprietes
    attendent {"name", "um", "value"} ; le format exact des pas n'a pas ete trouve (ExerciseDataNotValid).
    A poursuivre avec scripts/test_writeback.py. Les series reelles restent stockees cote backend.
Toute erreur est renvoyee sous forme de texte, les resultats restent en local.
"""

from __future__ import annotations

import logging
from datetime import date
from typing import Any

from app.mywellness import client as mw
from app.mywellness.models import Workout, WorkoutResults, partition_iso

log = logging.getLogger(__name__)


def steps_payload(sets: list[Any]) -> list[dict[str, Any]]:
    steps = []
    for s in sets:
        if getattr(s, "skipped", False):
            continue
        data = []
        if getattr(s, "reps", None) is not None:
            data.append({"physicalProperty": "IsoReps", "value": s.reps})
        if getattr(s, "weight_kg", None) is not None:
            data.append({"physicalProperty": "IsoWeight", "value": s.weight_kg})
        if getattr(s, "duration_s", None) is not None:
            data.append({"physicalProperty": "Duration", "value": s.duration_s})
        if getattr(s, "rest_s", None) is not None:
            data.append({"physicalProperty": "RestTime", "value": s.rest_s})
        if data:
            steps.append({"data": data})
    return steps


def find_open_session(client: mw.MywellnessClient, workout_id: str, day: date) -> tuple[int, str, str | None] | None:
    """(idCr, partitionDate, facilityId) de la seance performee du jour pour cette seance prescrite."""
    for item in client.activity_history(day, day):
        if str(item.get("userWorkoutSessionId")) == workout_id and partition_iso(item.get("partitionDate")) == day.isoformat():
            return int(item["idCr"]), str(item["partitionDate"]), item.get("facilityId")
    return None


def push_results(
    client: mw.MywellnessClient,
    workout: Workout,
    results: WorkoutResults,
    facility_id: str | None = None,
    close: bool = True,
    only_positions: set[int] | None = None,
) -> tuple[str, str]:
    """Retourne (statut, detail). statut = ok | partial | error | nothing."""
    day = date.fromisoformat(results.date) if results.date else date.today()
    by_pos = {e.position: e for e in workout.exercises}
    todo = [ex for ex in results.exercises if steps_payload(ex.sets) and (only_positions is None or ex.position in only_positions)]
    if not todo:
        return "nothing", "aucune serie a ecrire"

    opened = find_open_session(client, workout.id, day)
    if opened is None:
        try:
            started = client.start_workout_session(workout.id, facility_id)
        except mw.MywellnessError as exc:
            return "error", f"StartWorkoutSession: {exc}"
        if started.get("notFound"):
            return "error", "StartWorkoutSession: seance inconnue"
        ws = started.get("workoutSession") or started
        id_cr = ws.get("idCr")
        partition = str(ws.get("partitionDate") or day.strftime("%Y%m%d"))
        fac_id = facility_id
    else:
        id_cr, partition, fac_id = opened
        fac_id = facility_id or fac_id

    errors: list[str] = []
    written = 0
    for ex in todo:
        # Verifie le 2026-09-30 sur une seance ouverte : MarkPhysicalActivityAsDone marque l'exercice fait
        # (statut Done, manuallyDone, series = valeurs prescrites, client "EndUserWebSite"), visible dans
        # l'app et dans GetCurrentWorkoutSession en moins de 5 s. SavePerformedPhysicalActivity (series
        # reelles) attend un summaryData.stepData dont le format n'a pas ete trouve (ExerciseDataNotValid).
        try:
            res = client.mark_physical_activity_as_done(
                {"position": ex.position, "userWorkoutSessionId": workout.id, "idCr": id_cr, "partitionDate": int(str(partition))},
                fac_id,
            ) or {}
            if isinstance(res, dict) and (res.get("performedPhysicalActivityId") or res.get("physicalActivityId")):
                written += 1
            else:
                errors.append(f"pos {ex.position}: reponse inattendue {str(res)[:80]}")
        except mw.MywellnessError as exc:
            errors.append(f"pos {ex.position}: {exc}")
    if close:
        try:
            client.close_workout_session(id_cr, partition, fac_id)
        except mw.MywellnessError as exc:
            errors.append(f"CloseWorkoutSession: {exc}")
    detail = f"idCr={id_cr} partitionDate={partition} exercices ecrits={written}/{len(todo)}"
    if errors:
        detail += "; " + "; ".join(errors)
    if written == 0:
        return "error", detail
    return ("partial" if errors else "ok"), detail
