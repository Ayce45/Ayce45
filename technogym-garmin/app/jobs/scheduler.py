"""Job planifie : push du workout du jour vers Garmin Connect chaque matin (PUSH_HOUR, TZ)."""

from __future__ import annotations

import logging
from typing import Any

from apscheduler.schedulers.background import BackgroundScheduler
from apscheduler.triggers.cron import CronTrigger

log = logging.getLogger(__name__)


def run_daily_push(state: Any) -> None:
    from app.garmin.push import push_today

    try:
        res = push_today(state)
        log.info("Push Garmin du jour ok: %s -> %s", res.get("name"), res.get("url"))
    except Exception as exc:
        log.exception("Push Garmin du jour en echec: %s", exc)


def start_scheduler(state: Any) -> BackgroundScheduler:
    s = state.settings
    sched = BackgroundScheduler(timezone=s.tz)
    sched.add_job(
        run_daily_push,
        CronTrigger(hour=int(s.push_hour), minute=0, timezone=s.tz),
        args=[state],
        id="garmin_push_today",
        replace_existing=True,
        misfire_grace_time=3600,
        coalesce=True,
    )
    sched.start()
    log.info("Scheduler demarre: push Garmin tous les jours a %02d:00 (%s)", int(s.push_hour), s.tz)
    return sched


def main() -> None:
    """Point d'entree autonome : `python -m app.jobs.scheduler` (bloquant)."""
    import time

    from app.api.main import build_state

    logging.basicConfig(level="INFO")
    state = build_state()
    sched = start_scheduler(state)
    try:
        while True:
            time.sleep(60)
    except KeyboardInterrupt:
        sched.shutdown()


if __name__ == "__main__":
    main()
