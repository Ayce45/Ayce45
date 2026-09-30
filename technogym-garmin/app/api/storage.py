"""Persistance SQLite : tokens d'appairage, resultats de seance, journal des push Garmin."""

from __future__ import annotations

import json
import secrets
import sqlite3
import threading
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

SCHEMA = """
CREATE TABLE IF NOT EXISTS pair_tokens (
    token TEXT PRIMARY KEY,
    label TEXT,
    created_at TEXT NOT NULL,
    last_seen_at TEXT,
    revoked INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS workout_results (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    workout_id TEXT NOT NULL,
    date TEXT NOT NULL,
    device TEXT,
    received_at TEXT NOT NULL,
    payload TEXT NOT NULL,
    mywellness_status TEXT,
    mywellness_detail TEXT
);
CREATE INDEX IF NOT EXISTS ix_results_workout ON workout_results(workout_id, date);
CREATE TABLE IF NOT EXISTS hr_samples (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    workout_id TEXT NOT NULL,
    id_cr INTEGER,
    date TEXT NOT NULL,
    t INTEGER NOT NULL,
    hr INTEGER NOT NULL,
    received_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS ix_hr_workout ON hr_samples(workout_id, date, t);
CREATE TABLE IF NOT EXISTS garmin_pushes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    date TEXT NOT NULL,
    workout_id TEXT NOT NULL,
    garmin_workout_id TEXT,
    scheduled INTEGER NOT NULL DEFAULT 0,
    pushed_at TEXT NOT NULL,
    response TEXT
);
"""


def utcnow() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


class Storage:
    def __init__(self, path: Path | str):
        self._path = Path(path)
        self._path.parent.mkdir(parents=True, exist_ok=True)
        self._lock = threading.RLock()
        self._conn = sqlite3.connect(str(self._path), check_same_thread=False)
        self._conn.row_factory = sqlite3.Row
        with self._lock:
            self._conn.executescript(SCHEMA)
            self._conn.commit()

    def close(self) -> None:
        self._conn.close()

    # ---------------------------------------------------------------- appairage
    def create_pair_token(self, label: str = "") -> str:
        token = secrets.token_urlsafe(24)
        with self._lock:
            self._conn.execute(
                "INSERT INTO pair_tokens(token, label, created_at) VALUES (?, ?, ?)", (token, label, utcnow())
            )
            self._conn.commit()
        return token

    def ensure_pair_token(self, token: str, label: str = "") -> None:
        """Enregistre un token fourni (idempotent)."""
        with self._lock:
            self._conn.execute(
                "INSERT OR IGNORE INTO pair_tokens(token, label, created_at) VALUES (?, ?, ?)", (token, label, utcnow())
            )
            self._conn.execute("UPDATE pair_tokens SET revoked = 0 WHERE token = ?", (token,))
            self._conn.commit()

    def check_pair_token(self, token: str | None) -> bool:
        if not token:
            return False
        with self._lock:
            row = self._conn.execute(
                "SELECT token FROM pair_tokens WHERE token = ? AND revoked = 0", (token,)
            ).fetchone()
            if row is None:
                return False
            self._conn.execute("UPDATE pair_tokens SET last_seen_at = ? WHERE token = ?", (utcnow(), token))
            self._conn.commit()
        return True

    def revoke_pair_token(self, token: str) -> None:
        with self._lock:
            self._conn.execute("UPDATE pair_tokens SET revoked = 1 WHERE token = ?", (token,))
            self._conn.commit()

    def list_pair_tokens(self) -> list[dict[str, Any]]:
        with self._lock:
            rows = self._conn.execute("SELECT * FROM pair_tokens ORDER BY created_at").fetchall()
        return [dict(r) | {"token": r["token"][:6] + "..."} for r in rows]

    # ---------------------------------------------------------------- resultats
    def save_results(self, workout_id: str, day: str, device: str, payload: dict[str, Any]) -> int:
        with self._lock:
            cur = self._conn.execute(
                "INSERT INTO workout_results(workout_id, date, device, received_at, payload) VALUES (?, ?, ?, ?, ?)",
                (workout_id, day, device, utcnow(), json.dumps(payload, ensure_ascii=False)),
            )
            self._conn.commit()
            return int(cur.lastrowid)

    def set_results_sync(self, result_id: int, status: str, detail: str = "") -> None:
        with self._lock:
            self._conn.execute(
                "UPDATE workout_results SET mywellness_status = ?, mywellness_detail = ? WHERE id = ?",
                (status, detail[:2000], result_id),
            )
            self._conn.commit()

    def list_results(self, workout_id: str | None = None, limit: int = 50) -> list[dict[str, Any]]:
        q = "SELECT * FROM workout_results"
        args: tuple[Any, ...] = ()
        if workout_id:
            q += " WHERE workout_id = ?"
            args = (workout_id,)
        q += " ORDER BY received_at DESC LIMIT ?"
        with self._lock:
            rows = self._conn.execute(q, args + (limit,)).fetchall()
        out = []
        for r in rows:
            d = dict(r)
            d["payload"] = json.loads(d["payload"])
            out.append(d)
        return out

    # ---------------------------------------------------------------- frequence cardiaque (montre)
    def add_hr_samples(self, workout_id: str, day: str, id_cr: int | None, samples: list[tuple[int, int]]) -> int:
        if not samples:
            return 0
        now = utcnow()
        with self._lock:
            self._conn.executemany(
                "INSERT INTO hr_samples(workout_id, id_cr, date, t, hr, received_at) VALUES (?, ?, ?, ?, ?, ?)",
                [(workout_id, id_cr, day, int(t), int(hr), now) for t, hr in samples if hr > 0],
            )
            self._conn.commit()
        return len(samples)

    def hr_samples(self, workout_id: str, day: str, since_t: int = 0) -> list[dict[str, int]]:
        with self._lock:
            rows = self._conn.execute(
                "SELECT t, hr FROM hr_samples WHERE workout_id = ? AND date = ? AND t >= ? ORDER BY t", (workout_id, day, since_t)
            ).fetchall()
        return [{"t": r["t"], "hr": r["hr"]} for r in rows]

    def hr_count(self, workout_id: str, day: str) -> int:
        with self._lock:
            row = self._conn.execute("SELECT COUNT(*) AS n FROM hr_samples WHERE workout_id = ? AND date = ?", (workout_id, day)).fetchone()
        return int(row["n"]) if row else 0

    # ---------------------------------------------------------------- push garmin
    def record_push(self, day: str, workout_id: str, garmin_workout_id: str | None, scheduled: bool, response: Any) -> None:
        with self._lock:
            self._conn.execute(
                "INSERT INTO garmin_pushes(date, workout_id, garmin_workout_id, scheduled, pushed_at, response) VALUES (?, ?, ?, ?, ?, ?)",
                (day, workout_id, garmin_workout_id, int(scheduled), utcnow(), json.dumps(response, default=str)[:20000]),
            )
            self._conn.commit()

    def last_push_for(self, day: str) -> dict[str, Any] | None:
        with self._lock:
            row = self._conn.execute(
                "SELECT * FROM garmin_pushes WHERE date = ? ORDER BY pushed_at DESC LIMIT 1", (day,)
            ).fetchone()
        return dict(row) if row else None
