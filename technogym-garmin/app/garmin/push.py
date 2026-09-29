"""Push d'une seance vers Garmin Connect : conversion, creation, planification au jour J."""

from __future__ import annotations

import logging
from datetime import date
from typing import Any

from app.garmin.client import GarminClient, GarminError
from app.garmin.converter import to_garmin_workout
from app.mywellness.models import Workout

log = logging.getLogger(__name__)

NAME_PREFIX = "TG "  # prefixe des workouts generes, pour les retrouver et les remplacer


def garmin_client(state: Any) -> GarminClient:
    if getattr(state, "garmin", None) is None:
        s = state.settings
        state.garmin = GarminClient(s.garmin_email, s.garmin_password, s.garth_home)
    return state.garmin


def workout_title(workout: Workout) -> str:
    return f"{NAME_PREFIX}{workout.name} {workout.date}"[:80]


def push_workout(state: Any, workout: Workout, schedule: bool = True, replace: bool = True) -> dict[str, Any]:
    """Cree le workout Garmin et le planifie a la date de la seance. Idempotent par (nom, date)."""
    g = garmin_client(state)
    title = workout_title(workout)
    payload, report = to_garmin_workout(workout, name=title)

    removed: list[Any] = []
    if replace:
        try:
            for w in g.list_workouts(200):
                if str(w.get("workoutName", "")).startswith(NAME_PREFIX) and str(w.get("workoutName")) == title:
                    g.delete_workout(w["workoutId"])
                    removed.append(w["workoutId"])
        except GarminError as exc:
            log.warning("Nettoyage des anciens workouts impossible: %s", exc)

    created = g.upload_workout(payload)
    garmin_id = created.get("workoutId") if isinstance(created, dict) else None
    scheduled: dict[str, Any] | None = None
    if schedule and garmin_id:
        try:
            scheduled = g.schedule_workout(garmin_id, workout.date)
        except GarminError as exc:
            scheduled = {"error": str(exc)}
    result = {
        "date": workout.date,
        "workout_id": workout.id,
        "garmin_workout_id": garmin_id,
        "name": title,
        "steps": len(payload["workoutSegments"][0]["workoutSteps"]),
        "mapping": report,
        "replaced": removed,
        "scheduled": scheduled,
        "url": f"https://connect.garmin.com/modern/workout/{garmin_id}" if garmin_id else None,
    }
    state.storage.record_push(workout.date, workout.id, str(garmin_id) if garmin_id else None, bool(scheduled and "error" not in scheduled), {"created": created, "scheduled": scheduled})
    return result


def push_today(state: Any, day: date | None = None) -> dict[str, Any]:
    workout = state.program.today(day)
    return push_workout(state, workout)
