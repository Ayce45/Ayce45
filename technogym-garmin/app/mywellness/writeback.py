"""Retour des resultats vers Mywellness (experimental, desactive par defaut).

Flux deduit des signatures d'erreur des actions (docs/mywellness-api.md) :
  1. StartWorkoutSession {userWorkoutSessionId}          -> seance performee (idCr, partitionDate)
  2. SavePerformedPhysicalActivity {...} par exercice    -> series faites
  3. CloseWorkoutSession {idCr, partitionDate}

Le format exact de summaryData n'a pas pu etre confirme sans polluer l'historique de l'utilisateur.
Toute erreur est capturee et renvoyee sous forme de texte : les resultats restent stockes en local.
"""

from __future__ import annotations

import logging
from datetime import date
from typing import Any

from app.mywellness import client as mw
from app.mywellness.models import Workout, WorkoutResults

log = logging.getLogger(__name__)


def _steps_payload(sets: list[Any]) -> list[dict[str, Any]]:
    steps = []
    for s in sets:
        if s.skipped:
            continue
        data = []
        if s.reps is not None:
            data.append({"physicalProperty": "IsoReps", "value": s.reps})
        if s.weight_kg is not None:
            data.append({"physicalProperty": "IsoWeight", "value": s.weight_kg})
        if s.duration_s is not None:
            data.append({"physicalProperty": "Duration", "value": s.duration_s})
        if s.rest_s is not None:
            data.append({"physicalProperty": "RestTime", "value": s.rest_s})
        steps.append({"data": data})
    return steps


def push_results(client: mw.MywellnessClient, workout: Workout, results: WorkoutResults, facility_id: str | None = None) -> tuple[str, str]:
    """Retourne (statut, detail). statut = ok | partial | error."""
    try:
        started = client.start_workout_session(workout.id, facility_id)
    except mw.MywellnessError as exc:
        return "error", f"StartWorkoutSession: {exc}"
    if started.get("notFound"):
        return "error", "StartWorkoutSession: seance inconnue"
    id_cr = started.get("idCr") or (started.get("workoutSession") or {}).get("idCr")
    partition = started.get("partitionDate") or (started.get("workoutSession") or {}).get("partitionDate") or date.today().strftime("%Y%m%d")
    errors: list[str] = []
    by_pos = {e.position: e for e in workout.exercises}
    for ex in results.exercises:
        target = by_pos.get(ex.position)
        steps = _steps_payload(ex.sets)
        if not steps:
            continue
        payload: dict[str, Any] = {
            "idCr": id_cr,
            "partitionDate": partition,
            "position": ex.position,
            "physicalActivityId": ex.physical_activity_id or (target.physical_activity_id if target else ""),
            "userWorkoutSessionId": workout.id,
            "summaryData": {"steps": steps},
        }
        try:
            client.save_performed_physical_activity(payload, facility_id)
        except mw.MywellnessError as exc:
            errors.append(f"pos {ex.position}: {exc}")
    try:
        client.close_workout_session(id_cr, str(partition), facility_id)
    except mw.MywellnessError as exc:
        errors.append(f"CloseWorkoutSession: {exc}")
    if not errors:
        return "ok", f"idCr={id_cr} partitionDate={partition}"
    status = "partial" if len(errors) < max(1, len(results.exercises)) else "error"
    return status, "; ".join(errors)
