"""Interface web de synchronisation : identifiants saisis dans le navigateur, un bouton, les workouts Garmin.

Servie par le backend sur GET /  (et GET /ui). Les identifiants sont gardes en memoire pour la duree du
processus et, si la case "se souvenir" est cochee, dans data/credentials.json (fichier local, hors git).
Aucun identifiant n'est necessaire dans .env pour utiliser cette page.
"""

from __future__ import annotations

import json
import logging
import threading
from datetime import date
from pathlib import Path
from typing import Any

from fastapi import APIRouter, Form, Request
from fastapi.responses import HTMLResponse, JSONResponse

from app.garmin.client import GarminClient, GarminError
from app.garmin.push import NAME_PREFIX
from app.garmin.converter import to_garmin_workout
from app.mywellness import client as mw
from app.mywellness.program import ProgramService

log = logging.getLogger("app.ui")

router = APIRouter()


class SyncState:
    """Identifiants et clients de la session UI (independants du .env)."""

    def __init__(self, data_dir: Path):
        self.data_dir = data_dir
        self.cred_path = data_dir / "credentials.json"
        self.lock = threading.RLock()
        self.creds: dict[str, str] = {}
        self.mywellness: mw.MywellnessClient | None = None
        self.program: ProgramService | None = None
        self.garmin: GarminClient | None = None
        self.last: dict[str, Any] = {}
        self.running = False
        self.load()

    def load(self) -> None:
        if self.cred_path.exists():
            try:
                self.creds = json.loads(self.cred_path.read_text(encoding="utf-8"))
            except ValueError:
                self.creds = {}

    def save(self) -> None:
        self.data_dir.mkdir(parents=True, exist_ok=True)
        self.cred_path.write_text(json.dumps(self.creds), encoding="utf-8")
        try:
            self.cred_path.chmod(0o600)
        except OSError:
            pass

    def forget(self) -> None:
        self.creds = {}
        self.mywellness = None
        self.program = None
        self.garmin = None
        if self.cred_path.exists():
            self.cred_path.unlink()

    def set_credentials(self, mw_email: str, mw_password: str, g_email: str, g_password: str, remember: bool) -> None:
        with self.lock:
            changed = (mw_email, mw_password) != (self.creds.get("mywellness_email"), self.creds.get("mywellness_password"))
            gchanged = (g_email, g_password) != (self.creds.get("garmin_email"), self.creds.get("garmin_password"))
            self.creds = {
                "mywellness_email": mw_email, "mywellness_password": mw_password,
                "garmin_email": g_email, "garmin_password": g_password,
            }
            if changed or self.mywellness is None:
                self.mywellness = mw.MywellnessClient(mw_email, mw_password)
                self.program = ProgramService(self.mywellness, cache_ttl=60)
            if gchanged or self.garmin is None:
                self.garmin = GarminClient(g_email, g_password, self.data_dir / "garth-ui")
            if remember:
                self.save()
            elif self.cred_path.exists():
                self.cred_path.unlink()

    def run_sync(self, schedule_today: bool = True, replace: bool = True) -> dict[str, Any]:
        """Cree un workout Garmin par seance du programme ; planifie la seance du jour."""
        with self.lock:
            if self.running:
                return {"ok": False, "error": "Synchronisation deja en cours"}
            self.running = True
        try:
            assert self.program is not None and self.garmin is not None
            user = self.mywellness.login() if self.mywellness else None  # verifie les identifiants Mywellness
            prog = self.program.program(force=True)
            today = self.program.pick_session()
            workouts = self.program.all_workouts()
            existing = {}
            try:
                for w in self.garmin.list_workouts(200):
                    name = str(w.get("workoutName", ""))
                    if name.startswith(NAME_PREFIX):
                        existing.setdefault(name, []).append(w["workoutId"])
            except GarminError as exc:
                log.warning("Liste des workouts Garmin indisponible: %s", exc)
            created = []
            for w in workouts:
                title = f"{NAME_PREFIX}{w.name}"[:80]
                payload, report = to_garmin_workout(w, name=title)
                payload["description"] = f"{prog.get('name', '')} : {w.name}. Synchronise depuis Mywellness le {date.today().isoformat()}."[:1024]
                removed = []
                if replace:
                    for wid in existing.get(title, []):
                        try:
                            self.garmin.delete_workout(wid)
                            removed.append(wid)
                        except GarminError as exc:
                            log.warning("Suppression %s impossible: %s", wid, exc)
                res = self.garmin.upload_workout(payload)
                gid = res.get("workoutId") if isinstance(res, dict) else None
                scheduled = None
                if schedule_today and gid and str(today.get("id")) == w.id:
                    try:
                        scheduled = self.garmin.schedule_workout(gid, date.today().isoformat())
                    except GarminError as exc:
                        scheduled = {"error": str(exc)}
                created.append({
                    "name": title, "workout_id": w.id, "garmin_workout_id": gid,
                    "url": f"https://connect.garmin.com/modern/workout/{gid}" if gid else None,
                    "exercises": len(w.exercises), "steps": len(payload["workoutSegments"][0]["workoutSteps"]),
                    "scheduled_today": bool(scheduled and "error" not in scheduled),
                    "replaced": removed,
                    "fallbacks": [r["name"] for r in report if r["method"] == "fallback"],
                })
            self.last = {
                "ok": True, "at": date.today().isoformat(), "program": prog.get("name"),
                "facility": user.facilities[0].name if user and user.facilities else "",
                "today": today.get("name"), "workouts": created,
            }
            return self.last
        except mw.LoginError as exc:
            return {"ok": False, "error": f"Identifiants Mywellness refuses : {exc}"}
        except (mw.MywellnessError, GarminError) as exc:
            return {"ok": False, "error": str(exc)}
        except Exception as exc:  # pragma: no cover
            log.exception("Synchronisation en echec")
            return {"ok": False, "error": f"Erreur inattendue : {exc}"}
        finally:
            with self.lock:
                self.running = False


PAGE = """<!doctype html>
<html lang="fr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Technogym vers Garmin</title>
<style>
:root{--bg:#0f1115;--card:#181b22;--fg:#e8e8ea;--muted:#9aa0a6;--accent:#e85d04;--ok:#3ecf8e;--err:#ff6b6b}
body{margin:0;background:var(--bg);color:var(--fg);font:16px/1.45 system-ui,-apple-system,Segoe UI,Roboto,sans-serif}
main{max-width:720px;margin:0 auto;padding:24px 16px}
h1{font-size:1.5rem;margin:0 0 4px}h1 span{color:var(--accent)}p.lead{color:var(--muted);margin-top:0}
.card{background:var(--card);border-radius:12px;padding:20px;margin:16px 0}
fieldset{border:0;padding:0;margin:0 0 12px}legend{font-weight:600;margin-bottom:8px;color:var(--accent)}
label{display:block;font-size:.9rem;color:var(--muted);margin:8px 0 4px}
input[type=text],input[type=email],input[type=password]{width:100%;box-sizing:border-box;padding:10px 12px;border-radius:8px;border:1px solid #2a2f3a;background:#0f1115;color:var(--fg);font-size:1rem}
.row{display:grid;grid-template-columns:1fr 1fr;gap:12px}@media(max-width:560px){.row{grid-template-columns:1fr}}
button{background:var(--accent);color:#fff;border:0;border-radius:10px;padding:12px 20px;font-size:1.05rem;font-weight:600;cursor:pointer;width:100%;margin-top:8px}
button[disabled]{opacity:.6;cursor:wait}button.secondary{background:#2a2f3a;margin-top:12px}
.check{display:flex;align-items:center;gap:8px;color:var(--muted);font-size:.9rem;margin-top:10px}
#result{display:none}.ok{color:var(--ok)}.err{color:var(--err)}
table{width:100%;border-collapse:collapse;margin-top:8px}td,th{padding:8px 6px;border-bottom:1px solid #2a2f3a;text-align:left;font-size:.95rem}
a{color:#8ab4f8}small{color:var(--muted)}.pill{display:inline-block;background:#2a2f3a;border-radius:999px;padding:2px 8px;font-size:.8rem;margin-left:6px}
</style></head><body><main>
<h1><span>Technogym</span> vers Garmin</h1>
<p class="lead">Saisis tes identifiants, clique, et les seances de ton programme Mywellness deviennent des workouts Garmin Connect (la seance du jour est planifiee sur le calendrier).</p>
<form class="card" id="f" onsubmit="return go(event)">
  <fieldset><legend>Technogym / Mywellness</legend>
    <div class="row"><div><label>Email</label><input type="email" name="mw_email" required value="__MW_EMAIL__"></div>
    <div><label>Mot de passe</label><input type="password" name="mw_password" required value="__MW_PASSWORD__"></div></div></fieldset>
  <fieldset><legend>Garmin Connect</legend>
    <div class="row"><div><label>Email</label><input type="email" name="g_email" required value="__G_EMAIL__"></div>
    <div><label>Mot de passe</label><input type="password" name="g_password" required value="__G_PASSWORD__"></div></div></fieldset>
  <label class="check"><input type="checkbox" name="remember" __REMEMBER__> Se souvenir des identifiants sur cet ordinateur (data/credentials.json, jamais dans le depot)</label>
  <label class="check"><input type="checkbox" name="schedule" checked> Planifier la seance du jour dans le calendrier Garmin</label>
  <button id="btn" type="submit">Synchroniser vers Garmin</button>
  <button class="secondary" type="button" onclick="forget()">Oublier les identifiants</button>
</form>
<div class="card" id="result"></div>
<p><small>Le backend tourne en local sur cette machine. Les identifiants ne sont envoyes qu'a core.mywellness.com et sso.garmin.com.
Pour le compagnon de seance sur la montre, voir <a href="/docs" target="_blank">l'API</a> et le README.</small></p>
<script>
async function go(e){e.preventDefault();const b=document.getElementById('btn');b.disabled=true;b.textContent='Connexion et synchronisation...';
const r=document.getElementById('result');r.style.display='block';r.innerHTML='<p>Lecture du programme Mywellness, creation des workouts Garmin (environ une minute)...</p>';
try{const res=await fetch('/ui/sync',{method:'POST',body:new FormData(document.getElementById('f'))});const j=await res.json();render(j);}
catch(err){r.innerHTML='<p class="err">Erreur : '+err+'</p>';}
b.disabled=false;b.textContent='Synchroniser vers Garmin';return false;}
function render(j){const r=document.getElementById('result');if(!j.ok){r.innerHTML='<p class="err">'+j.error+'</p>';return;}
let h='<p class="ok">Synchronisation terminee. Programme : <b>'+j.program+'</b>'+(j.facility?' ('+j.facility+')':'')+'. Seance du jour : <b>'+j.today+'</b>.</p><table><tr><th>Workout Garmin</th><th>Exercices</th><th>Steps</th><th></th></tr>';
for(const w of j.workouts){h+='<tr><td><a href="'+w.url+'" target="_blank">'+w.name+'</a>'+(w.scheduled_today?'<span class="pill">planifie aujourd\\'hui</span>':'')+'</td><td>'+w.exercises+'</td><td>'+w.steps+'</td><td>'+(w.fallbacks.length?'<small>sans equivalent Garmin : '+w.fallbacks.join(', ')+'</small>':'')+'</td></tr>';}
h+='</table><p><small>Ouvre Garmin Connect (web ou mobile) : Entrainement > Workouts. Sur la montre, les workouts se synchronisent au prochain passage de Garmin Connect Mobile.</small></p>';r.innerHTML=h;}
async function forget(){await fetch('/ui/forget',{method:'POST'});location.reload();}
</script></main></body></html>"""


def render_page(state: SyncState) -> str:
    c = state.creds
    page = PAGE
    for key, val in (("__MW_EMAIL__", c.get("mywellness_email", "")), ("__MW_PASSWORD__", c.get("mywellness_password", "")),
                     ("__G_EMAIL__", c.get("garmin_email", "")), ("__G_PASSWORD__", c.get("garmin_password", ""))):
        page = page.replace(key, val.replace("&", "&amp;").replace('"', "&quot;"))
    return page.replace("__REMEMBER__", "checked" if state.cred_path.exists() else "")


def attach(app: Any, data_dir: Path) -> SyncState:
    state = SyncState(data_dir)

    @router.get("/", response_class=HTMLResponse, include_in_schema=False)
    @router.get("/ui", response_class=HTMLResponse, include_in_schema=False)
    def ui_page() -> HTMLResponse:
        return HTMLResponse(render_page(state))

    @router.post("/ui/sync", include_in_schema=False)
    def ui_sync(
        request: Request,
        mw_email: str = Form(...), mw_password: str = Form(...),
        g_email: str = Form(...), g_password: str = Form(...),
        remember: str | None = Form(default=None), schedule: str | None = Form(default=None),
    ) -> JSONResponse:
        state.set_credentials(mw_email.strip(), mw_password, g_email.strip(), g_password, remember is not None)
        return JSONResponse(state.run_sync(schedule_today=schedule is not None))

    @router.post("/ui/forget", include_in_schema=False)
    def ui_forget() -> dict[str, bool]:
        state.forget()
        return {"ok": True}

    @router.get("/ui/last", include_in_schema=False)
    def ui_last() -> dict[str, Any]:
        return state.last

    app.include_router(router)
    return state
