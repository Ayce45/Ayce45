"""Backend FastAPI : seance du jour, resultats montre, historique, push Garmin."""

from __future__ import annotations

import logging
import os
from contextlib import asynccontextmanager
from datetime import date
from typing import Any

from fastapi import Depends, FastAPI, Header, HTTPException, Query, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from pydantic import BaseModel

from app.config import Settings, get_settings
from app.mywellness import client as mw
from app.mywellness import history as hist
from app.mywellness import writeback
from app.mywellness.live import LiveService, LiveState
from app.mywellness.models import Workout, WorkoutResults
from app.mywellness.program import ProgramService
from app.api.storage import Storage

log = logging.getLogger("app.api")


class AppState:
    settings: Settings
    storage: Storage
    mywellness: mw.MywellnessClient | None
    program: ProgramService
    live: Any = None
    ui: Any = None
    garmin: Any = None
    scheduler: Any = None


def build_state(settings: Settings | None = None, mywellness_client: mw.MywellnessClient | None = None) -> AppState:
    s = settings or get_settings()
    st = AppState()
    st.settings = s
    st.storage = Storage(s.database_path)
    if mywellness_client is not None:
        st.mywellness = mywellness_client
    elif s.mywellness_email and s.mywellness_password:
        st.mywellness = mw.MywellnessClient(s.mywellness_email, s.mywellness_password)
    else:
        st.mywellness = None
    st.program = ProgramService(st.mywellness, cache_ttl=s.program_cache_ttl, override_path=s.program_override_path)
    st.live = LiveService(st.mywellness)
    if s.live_replay_path:
        st.live.replay_path = s.live_replay_path
        st.live.replay_step = s.live_replay_step
        log.warning("GET /live sert le rejeu %s (pas %.1fs), pas Technogym", s.live_replay_path, s.live_replay_step)
    return st


class HrBatch(BaseModel):
    """Lot d'echantillons cardio envoye par la montre (POST /live/hr)."""

    workout_id: str = ""
    id_cr: int | None = None
    date: str = ""
    samples: list[list[int]] = []   # [[t_epoch, bpm], ...]


def create_app(state: AppState | None = None, with_scheduler: bool = True) -> FastAPI:
    st = state or build_state()

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        if with_scheduler:
            try:
                from app.jobs.scheduler import start_scheduler

                st.scheduler = start_scheduler(st)
            except Exception as exc:  # pragma: no cover
                log.warning("Scheduler non demarre: %s", exc)
        yield
        if st.scheduler is not None:
            st.scheduler.shutdown(wait=False)
        st.storage.close()

    app = FastAPI(title="Technogym vers Garmin", version="0.1.0", lifespan=lifespan)
    app.state.ctx = st

    @app.exception_handler(RequestValidationError)
    async def _log_422(request: Request, exc: RequestValidationError) -> JSONResponse:
        # utile pour voir ce que la montre envoie vraiment (le SDK Connect IQ serialise a sa facon)
        body = await request.body()
        log.warning("422 %s %s body=%s erreurs=%s", request.method, request.url.path, body[:800], exc.errors()[:3])
        return JSONResponse(status_code=422, content={"detail": exc.errors()})

    # interface web de synchronisation (identifiants saisis dans le navigateur)
    from app.api import ui as _ui

    st.ui = _ui.attach(app, st.settings.database_path.parent)

    # ------------------------------------------------------------- securite
    def require_admin(x_admin_token: str | None = Header(default=None)) -> None:
        expected = st.settings.admin_token
        if expected and x_admin_token != expected:
            raise HTTPException(status_code=401, detail="X-Admin-Token invalide")

    def require_pair(
        x_pair_token: str | None = Header(default=None),
        token: str | None = Query(default=None),
    ) -> str:
        tok = x_pair_token or token
        if not st.storage.check_pair_token(tok):
            raise HTTPException(status_code=401, detail="Token d'appairage invalide")
        return str(tok)

    def require_pair_or_admin(
        x_pair_token: str | None = Header(default=None),
        x_admin_token: str | None = Header(default=None),
        token: str | None = Query(default=None),
    ) -> None:
        if st.storage.check_pair_token(x_pair_token or token):
            return
        expected = st.settings.admin_token
        if expected and x_admin_token == expected:
            return
        if not expected and not st.storage.list_pair_tokens():
            # installation vierge : on laisse lire pour tester en local
            return
        raise HTTPException(status_code=401, detail="Token d'appairage ou admin requis")

    @app.exception_handler(mw.MywellnessError)
    async def _mw_error(_: Request, exc: mw.MywellnessError) -> JSONResponse:
        code = 404 if isinstance(exc, mw.NotFoundError) else 502
        return JSONResponse(status_code=code, content={"detail": f"Mywellness: {exc}"})

    # ------------------------------------------------------------- endpoints
    @app.get("/health")
    def health() -> dict[str, Any]:
        return {
            "status": "ok",
            "mywellness_configured": st.mywellness is not None,
            "garmin_configured": bool(st.settings.garmin_email),
            "pair_tokens": len(st.storage.list_pair_tokens()),
        }

    class PairRequest(BaseModel):
        label: str = ""

    @app.post("/auth/pair", dependencies=[Depends(require_admin)])
    def pair(body: PairRequest | None = None) -> dict[str, str]:
        token = st.storage.create_pair_token((body.label if body else "") or "montre")
        return {"token": token, "header": "X-Pair-Token", "hint": "Saisir ce token dans les reglages de l'app Connect IQ"}

    @app.get("/auth/pair", dependencies=[Depends(require_admin)])
    def list_pairs() -> list[dict[str, Any]]:
        return st.storage.list_pair_tokens()

    @app.get("/workout/today", response_model=Workout, response_model_exclude_none=True, dependencies=[Depends(require_pair_or_admin)])
    def workout_today(day: date | None = None) -> Workout:
        if day is None and st.settings.today_override:
            day = date.fromisoformat(st.settings.today_override)
        return st.program.today(day)

    @app.get("/workout/all", response_model=list[Workout], response_model_exclude_none=True, dependencies=[Depends(require_pair_or_admin)])
    def workout_all() -> list[Workout]:
        return st.program.all_workouts()

    @app.get("/workout/{workout_id}", response_model=Workout, response_model_exclude_none=True, dependencies=[Depends(require_pair_or_admin)])
    def workout_by_id(workout_id: str) -> Workout:
        w = st.program.by_id(workout_id)
        if w is None:
            raise HTTPException(status_code=404, detail="Seance inconnue")
        return w

    @app.post("/workout/{workout_id}/results", dependencies=[Depends(require_pair_or_admin)])
    def workout_results(workout_id: str, body: WorkoutResults) -> dict[str, Any]:
        body.workout_id = workout_id
        day = body.date or date.today().isoformat()
        rid = st.storage.save_results(workout_id, day, body.device, body.model_dump(exclude_none=True))
        sync_status, detail = "stored", ""
        if os.environ.get("MYWELLNESS_WRITEBACK", "0") == "1" and st.mywellness is not None:
            workout = st.program.by_id(workout_id)
            if workout is None:
                sync_status, detail = "error", "seance inconnue dans le programme"
            else:
                sync_status, detail = writeback.push_results(st.mywellness, workout, body)
            st.storage.set_results_sync(rid, sync_status, detail)
        sets = sum(len(e.sets) for e in body.exercises)
        return {"id": rid, "stored": True, "sets": sets, "mywellness": sync_status, "detail": detail}

    @app.get("/workout/{workout_id}/live", response_model=LiveState, response_model_exclude_none=True, dependencies=[Depends(require_pair_or_admin)])
    def workout_live(workout_id: str, day: date | None = None) -> LiveState:
        """Ce que les machines Technogym ont deja enregistre aujourd'hui pour cette seance (poll de la montre)."""
        return st.live.state(workout_id, day)

    # --------------------------------------------------------- suivi live (seance courante Technogym)
    @app.get("/live", response_model=LiveState, response_model_exclude_none=True, dependencies=[Depends(require_pair_or_admin)])
    def live_current() -> LiveState:
        """Seance en cours cote Technogym (bornes, machines, app) : exercices faits, en cours, a faire."""
        state = st.live.current()
        if state.workout_id:
            state.hr_samples = st.storage.hr_count(state.workout_id, state.date)
        return state

    @app.post("/live/hr", dependencies=[Depends(require_pair_or_admin)])
    def live_hr(body: HrBatch) -> dict[str, Any]:
        """Echantillons cardio envoyes par la montre pendant la seance (stockes, puis ecrits par exercice)."""
        day = body.date or date.today().isoformat()
        wid = body.workout_id or st.live.current().workout_id or "unknown"
        n = st.storage.add_hr_samples(wid, day, body.id_cr, [(s[0], s[1]) for s in body.samples if len(s) >= 2])
        return {"stored": n, "workout_id": wid, "total": st.storage.hr_count(wid, day)}

    @app.post("/live/start", dependencies=[Depends(require_pair_or_admin)])
    def live_start(workout_id: str | None = None) -> dict[str, Any]:
        """Ouvre la seance du jour (ou celle donnee) cote Technogym, comme la borne ou l'app."""
        if st.mywellness is None:
            raise HTTPException(status_code=503, detail="Mywellness non configure")
        cur = st.live.current()
        if cur.has_current_workout:
            return {"started": False, "already_open": True, "workout_id": cur.workout_id, "id_cr": cur.id_cr}
        wid = workout_id or st.program.today().id
        res = st.mywellness.start_workout_session(wid)
        st.live._cache.clear()
        return {"started": not res.get("notFound"), "workout_id": wid, "response": res}

    @app.post("/live/close", dependencies=[Depends(require_pair_or_admin)])
    def live_close() -> dict[str, Any]:
        """Ferme la seance courante cote Technogym."""
        if st.mywellness is None:
            raise HTTPException(status_code=503, detail="Mywellness non configure")
        cur = st.live.current()
        if not cur.has_current_workout:
            return {"closed": False, "reason": "aucune seance ouverte"}
        partition = cur.date.replace("-", "")
        res = st.mywellness.close_workout_session(cur.id_cr, partition)
        st.live._cache.clear()
        return {"closed": True, "workout_id": cur.workout_id, "id_cr": cur.id_cr, "response": res}

    @app.get("/workout/{workout_id}/results", dependencies=[Depends(require_pair_or_admin)])
    def list_results(workout_id: str, limit: int = 20) -> list[dict[str, Any]]:
        return st.storage.list_results(workout_id, limit)

    @app.get("/history", response_model=list[hist.HistorySession], response_model_exclude_none=True, dependencies=[Depends(require_pair_or_admin)])
    def history(days: int = Query(default=30, ge=1, le=365), details: bool = False, limit: int = Query(default=20, ge=1, le=200)) -> list[hist.HistorySession]:
        if st.mywellness is None:
            raise HTTPException(status_code=503, detail="Mywellness non configure")
        sessions = hist.list_history(st.mywellness, days)[:limit]
        if details:
            sessions = [hist.get_session(st.mywellness, s) for s in sessions]
        return sessions

    @app.get("/history/{session_id}", response_model=hist.HistorySession, response_model_exclude_none=True, dependencies=[Depends(require_pair_or_admin)])
    def history_session(session_id: str, day: date | None = None) -> hist.HistorySession:
        if st.mywellness is None:
            raise HTTPException(status_code=503, detail="Mywellness non configure")
        for s in hist.list_history(st.mywellness, 365):
            if s.session_id == session_id and (day is None or s.date == day.isoformat()):
                return hist.get_session(st.mywellness, s)
        raise HTTPException(status_code=404, detail="Seance introuvable")

    @app.post("/garmin/push-today", dependencies=[Depends(require_admin)])
    def garmin_push_today(day: date | None = None, schedule: bool = True, replace: bool = True) -> dict[str, Any]:
        from app.garmin.push import push_workout

        workout = st.program.today(day)
        result = push_workout(st, workout, schedule=schedule, replace=replace)
        return result

    @app.get("/garmin/last-push", dependencies=[Depends(require_admin)])
    def garmin_last_push(day: date | None = None) -> dict[str, Any]:
        row = st.storage.last_push_for((day or date.today()).isoformat())
        return row or {}

    return app


def get_app() -> FastAPI:
    logging.basicConfig(level=os.environ.get("LOG_LEVEL", "INFO"))
    return create_app()
