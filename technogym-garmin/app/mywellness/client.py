"""Client HTTP pour l'API privee Mywellness (canal utilisateur final).

Reprend le flux d'authentification documente par technogym-mcp (health_mcp) et ajoute
les actions decouvertes pour le programme prescrit et le tracking manuel.
Tout est documente dans docs/mywellness-api.md.

Hotes :
  * https://core.mywellness.com       login
  * https://services.mywellness.com   donnees, sous /{facilityUrl}/Training/User/{userId}/<Action>

Toutes les requetes portent les en-tetes d'identification de l'app web enduserweb
(X-MWAPPS-APPID / X-MWAPPS-CLIENT), sans quoi l'API repond ClientApplicationNotTrusted.
"""

from __future__ import annotations

import logging
import threading
from dataclasses import dataclass, field
from datetime import date, timedelta
from typing import Any

import httpx

log = logging.getLogger(__name__)

CORE_URL = "https://core.mywellness.com"
SERVICES_URL = "https://services.mywellness.com"
WORKOUT_URL = "https://workout.mywellness.com"  # API "workout" de l'app mobile (seance courante)
APP_ID = "EC1D38D7-D359-48D0-A60C-D8C0B8FB9DF9"
APP_NAME = "enduserweb"
APP_VERSION = "1.0"

LOGIN_PATH = "/v2/enduser/authentication/login"

# Actions Training/User (voir docs/mywellness-api.md)
ACTIVITY_HISTORY = "ActivityHistory"
PERFORMED_SESSION_BY_IDCR = "GetPerformedWorkoutSessionByIdCr"
HR_SESSION = "GetHrSession"
USER_TRAINING_PROGRAM = "GetUserTrainingProgram"
USER_WORKOUT_SESSION = "GetUserWorkoutSession"
USER_WORKOUT_SESSION_PA = "GetUserWorkoutSessionPhysicalActivity"
CURRENT_WORKOUT_SESSION = "GetCurrentWorkoutSession"
START_WORKOUT_SESSION = "StartWorkoutSession"
CLOSE_WORKOUT_SESSION = "CloseWorkoutSession"
SAVE_PERFORMED_PA = "SavePerformedPhysicalActivity"
MARK_PA_DONE = "MarkPhysicalActivityAsDone"
DELETE_PERFORMED_PA = "DeletePerformedPhysicalActivity"
MY_MOVERGY = "MyMovergy"
GOAL = "Goal"

_AUTH_ERROR_DETAILS = {
    "TokenNotValid",
    "InvalidToken",
    "TokenExpired",
    "NotAuthenticated",
    "Unauthorized",
    "UserNotLogged",
}


class MywellnessError(Exception):
    """Erreur de base."""


class LoginError(MywellnessError):
    """Echec d'authentification."""


class NotFoundError(MywellnessError):
    """Ressource absente."""


@dataclass
class Facility:
    id: str
    url: str
    name: str


@dataclass
class UserInfo:
    user_id: str
    first_name: str
    measurement_system: str
    culture: str
    facilities: list[Facility] = field(default_factory=list)


def _errors_text(body: dict[str, Any]) -> str:
    return "; ".join(
        str(e.get("details") or e.get("errorMessage") or e.get("message") or e)
        for e in body.get("errors") or []
    )


def _looks_like_auth_error(errors: list[dict[str, Any]], status: int) -> bool:
    if status in (401, 403):
        return True
    for e in errors:
        details = str(e.get("details") or e.get("message") or "")
        if details in _AUTH_ERROR_DETAILS or "token" in details.lower():
            return True
    return False


def ymd(d: date) -> str:
    return d.strftime("%Y%m%d")


def partition_to_iso(p: Any) -> str:
    s = str(p or "")
    return f"{s[:4]}-{s[4:6]}-{s[6:8]}" if len(s) == 8 and s.isdigit() else s


class MywellnessClient:
    """Client thread-safe, login paresseux, re-login unique sur erreur d'auth."""

    def __init__(self, email: str, password: str, timeout: float = 60.0, transport: httpx.BaseTransport | None = None):
        if not email or not password:
            raise LoginError("MYWELLNESS_EMAIL et MYWELLNESS_PASSWORD doivent etre definis")
        self._email = email
        self._password = password
        self._lock = threading.RLock()
        self._http = httpx.Client(
            timeout=timeout,
            follow_redirects=True,
            transport=transport,
            headers={
                "User-Agent": "technogym-garmin/0.1",
                "Accept": "application/json",
                "X-MWAPPS-APPID": APP_ID,
                "X-MWAPPS-CLIENT": APP_NAME,
                "X-MWAPPS-CLIENTVERSION": f"{APP_VERSION},{APP_NAME}",
            },
        )
        self._user: UserInfo | None = None
        self._token: str | None = None
        self._facility_url: str | None = None

    def close(self) -> None:
        self._http.close()

    # ------------------------------------------------------------------ auth
    @property
    def user(self) -> UserInfo:
        return self.ensure_login()

    def login(self) -> UserInfo:
        with self._lock:
            log.info("Connexion Mywellness (%s)", self._email)
            try:
                r = self._http.post(
                    f"{CORE_URL}{LOGIN_PATH}",
                    json={"username": self._email, "password": self._password, "keepMeLoggedIn": True},
                    headers={"Authorization": ""},
                )
                r.raise_for_status()
                body = r.json()
            except (httpx.HTTPError, ValueError) as exc:
                raise LoginError(f"Requete de login en echec: {exc}") from exc
            if body.get("errors"):
                raise LoginError(f"Login refuse: {_errors_text(body)}")
            data = body.get("data") or body
            token = data.get("token")
            user = parse_user(data)
            if not token or not user:
                raise LoginError(f"Reponse de login inattendue (result={data.get('result')!r})")
            self._token = token
            self._user = user
            self._http.headers["Authorization"] = f"Bearer {token}"
            if self._facility_url is None and user.facilities:
                self._facility_url = user.facilities[0].url
            return user

    def ensure_login(self) -> UserInfo:
        with self._lock:
            return self._user if self._user is not None else self.login()

    def set_facility(self, url_or_id: str) -> None:
        """Choisit la salle utilisee dans l'URL des actions Training."""
        user = self.ensure_login()
        for f in user.facilities:
            if url_or_id in (f.url, f.id):
                self._facility_url = f.url
                return
        raise MywellnessError(f"Salle inconnue: {url_or_id}")

    @property
    def facility_url(self) -> str:
        user = self.ensure_login()
        if not self._facility_url:
            if not user.facilities:
                raise MywellnessError("Compte sans salle: impossible d'adresser les actions Training")
            self._facility_url = user.facilities[0].url
        return self._facility_url

    def facility_url_for_id(self, facility_id: str | None) -> str:
        for f in self.ensure_login().facilities:
            if f.id == facility_id:
                return f.url
        return self.facility_url

    # ------------------------------------------------------------- transport
    def post_action(self, action: str, content: dict[str, Any] | None = None, facility_url: str | None = None) -> Any:
        """POST services.mywellness.com/{facility}/Training/User/{userId}/{action}."""
        user = self.ensure_login()
        fac = facility_url or self.facility_url
        url = f"{SERVICES_URL}/{fac}/Training/User/{user.user_id}/{action}"
        return self._post_url(url, content or {})

    def post_path(self, path: str, content: dict[str, Any] | None = None) -> Any:
        return self._post_url(SERVICES_URL + path, content or {})

    def _post_url(self, url: str, content: dict[str, Any]) -> Any:
        for attempt in (1, 2):
            r = self._http.post(url, json=content)
            if r.status_code == 404:
                raise NotFoundError(f"Action inconnue: {url}")
            if r.status_code in (401, 403):
                body: dict[str, Any] = {"errors": [{"details": f"HTTP {r.status_code}"}]}
            else:
                try:
                    r.raise_for_status()
                    body = r.json()
                except httpx.HTTPStatusError as exc:
                    raise MywellnessError(str(exc)) from exc
                except ValueError as exc:
                    raise MywellnessError(f"Reponse non JSON depuis {url}") from exc
            errors = body.get("errors") or []
            if not errors:
                return body.get("data") if "data" in body else body
            if attempt == 1 and _looks_like_auth_error(errors, r.status_code):
                log.warning("Erreur d'auth sur %s, reconnexion", url)
                self.login()
                continue
            raise MywellnessError(f"{url.rsplit('/', 1)[-1]}: {_errors_text(body)}")
        raise MywellnessError("unreachable")

    # ------------------------------------------------------------ lecture
    def activity_history(self, from_date: date, to_date: date, only_workouts: bool = True) -> list[dict[str, Any]]:
        if from_date > to_date:
            from_date, to_date = to_date, from_date
        content: dict[str, Any] = {"startDay": ymd(from_date), "endDay": ymd(to_date)}
        if only_workouts:
            content["justThisType"] = "WorkoutSession"
        data = self.post_action(ACTIVITY_HISTORY, content) or {}
        items = list(data.get("items") or [])
        items.sort(key=lambda i: (str(i.get("partitionDate")), int(i.get("hour") or 0), int(i.get("minute") or 0)), reverse=True)
        return items

    def performed_session_raw(self, id_cr: int | str, day: date | str, facility_id: str | None = None) -> dict[str, Any]:
        partition = ymd(day) if isinstance(day, date) else str(day).replace("-", "")
        data = self.post_action(
            PERFORMED_SESSION_BY_IDCR,
            {"idCr": int(id_cr), "partitionDate": partition},
            facility_url=self.facility_url_for_id(facility_id),
        )
        if not data or not data.get("id"):
            raise NotFoundError(f"Seance {id_cr} du {partition} introuvable")
        return data

    def user_training_program_raw(self) -> dict[str, Any]:
        data = self.post_action(USER_TRAINING_PROGRAM, {}) or {}
        details = data.get("userTrainingProgramDetails")
        if not details:
            raise NotFoundError("Aucun programme d'entrainement assigne")
        return details

    def user_workout_session_raw(self, workout_session_id: str | None = None) -> dict[str, Any]:
        content = {"workoutSessionId": workout_session_id} if workout_session_id else {}
        data = self.post_action(USER_WORKOUT_SESSION, content) or {}
        return data.get("workoutSession") or {}

    def user_workout_session_physical_activity_raw(self, workout_session_id: str, position: int) -> dict[str, Any]:
        data = self.post_action(
            USER_WORKOUT_SESSION_PA, {"userWorkoutSessionId": workout_session_id, "position": int(position)}
        ) or {}
        pa = data.get("userPhysicalActivity")
        if not pa:
            raise NotFoundError(f"Exercice position {position} de la seance {workout_session_id} introuvable")
        return pa

    def current_workout_session(self) -> dict[str, Any]:
        return self.post_action(CURRENT_WORKOUT_SESSION, {}) or {}

    def current_workout(self) -> dict[str, Any]:
        """GET workout.mywellness.com/v2/enduser/workout/current : ce que l'app mobile interroge.

        Repond {"hasCurrentWorkout": false} hors seance ; pendant une seance ouverte sur une machine
        ou un kiosque, la seance courante (voir docs/live-poc.md). Appel leger, sans facilityUrl.
        """
        self.ensure_login()
        for attempt in (1, 2):
            r = self._http.get(f"{WORKOUT_URL}/v2/enduser/workout/current")
            if r.status_code in (401, 403) and attempt == 1:
                self.login()
                continue
            try:
                r.raise_for_status()
                body = r.json()
            except httpx.HTTPStatusError as exc:
                raise MywellnessError(str(exc)) from exc
            except ValueError as exc:
                raise MywellnessError("Reponse non JSON de workout/current") from exc
            if isinstance(body, dict) and body.get("errors"):
                raise MywellnessError(f"workout/current: {_errors_text(body)}")
            return body.get("data") if isinstance(body, dict) and "data" in body else body
        raise MywellnessError("unreachable")

    def movergy(self) -> int | None:
        return (self.post_action(MY_MOVERGY, {}) or {}).get("movergy")

    def goal(self) -> dict[str, Any]:
        return self.post_action(GOAL, {}) or {}

    def find_last_performed(self, user_workout_session_id: str, lookback_days: int = 365) -> dict[str, Any] | None:
        """Derniere execution (item ActivityHistory) d'une seance prescrite donnee."""
        today = date.today()
        for item in self.activity_history(today - timedelta(days=lookback_days), today):
            if str(item.get("userWorkoutSessionId")) == str(user_workout_session_id):
                return item
        return None

    # ----------------------------------------------------------- ecriture
    def start_workout_session(self, user_workout_session_id: str, facility_id: str | None = None) -> dict[str, Any]:
        """Ouvre une seance prescrite (cree l'instance performee, retourne idCr et partitionDate)."""
        return self.post_action(
            START_WORKOUT_SESSION,
            {"userWorkoutSessionId": user_workout_session_id},
            facility_url=self.facility_url_for_id(facility_id),
        ) or {}

    def close_workout_session(self, id_cr: int | None = None, partition_date: str | None = None, facility_id: str | None = None) -> dict[str, Any]:
        content: dict[str, Any] = {}
        if id_cr is not None:
            content["idCr"] = int(id_cr)
        if partition_date:
            content["partitionDate"] = str(partition_date).replace("-", "")
        return self.post_action(CLOSE_WORKOUT_SESSION, content, facility_url=self.facility_url_for_id(facility_id)) or {}

    def save_performed_physical_activity(self, payload: dict[str, Any], facility_id: str | None = None) -> dict[str, Any]:
        """Tracking manuel d'un exercice. Voir docs/mywellness-api.md pour le format du payload."""
        fac = self.facility_url_for_id(facility_id)
        content = {"facilityUrl": fac, **payload}
        return self.post_action(SAVE_PERFORMED_PA, content, facility_url=fac) or {}

    def mark_physical_activity_as_done(self, payload: dict[str, Any], facility_id: str | None = None) -> dict[str, Any]:
        return self.post_action(MARK_PA_DONE, payload, facility_url=self.facility_url_for_id(facility_id)) or {}


def parse_user(data: dict[str, Any]) -> UserInfo | None:
    uc = data.get("userContext") or {}
    uid = uc.get("id")
    if not uid:
        return None
    return UserInfo(
        user_id=str(uid),
        first_name=str(uc.get("firstName", "")),
        measurement_system=str(uc.get("measurementSystem", "")),
        culture=str(uc.get("defaultCulture", "")),
        facilities=[
            Facility(id=str(f.get("id", "")), url=str(f.get("url", "")), name=str(f.get("name", "")))
            for f in data.get("facilities") or []
        ],
    )
