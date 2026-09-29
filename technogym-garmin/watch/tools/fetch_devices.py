#!/usr/bin/env python
"""Telecharge les definitions d'appareils et polices Connect IQ sans le SDK Manager graphique.

Reproduit le flux du SDK Manager (documente par le projet ciqw de Jean Schurger) :
  1. login SSO Garmin (sso.garmin.com/sso/signin, service = sso/embed) -> ticket
  2. echange du ticket contre un jeton OAuth client CIQ_SDK_MANAGER (services.garmin.com/api/oauth/token)
  3. api.gcs.garmin.com/ciq-product-onboarding/devices, /devices/{partNumber}/ciqInfo, /fonts

Identifiants lus dans GARMIN_EMAIL / GARMIN_PASSWORD (.env a la racine du projet).
Destination : ~/.Garmin/ConnectIQ/Devices et ~/.Garmin/ConnectIQ/Fonts (emplacement attendu par monkeyc).

Usage : python watch/tools/fetch_devices.py [--list] [--all] [device ...]
"""

from __future__ import annotations

import argparse
import io
import os
import re
import sys
import zipfile
from pathlib import Path

from curl_cffi import requests
from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parents[2]
load_dotenv(ROOT / ".env")

SSO = "https://sso.garmin.com/sso"
SERVICE = f"{SSO}/embed"
SGC = "https://services.garmin.com"
APIGCS = "https://api.gcs.garmin.com"
CIQ_HOME = Path(os.environ.get("CIQ_HOME", Path.home() / ".Garmin" / "ConnectIQ"))

DEFAULT_DEVICES = [
    # Forerunner
    "fr165", "fr165m", "fr245", "fr245m", "fr255", "fr255m", "fr255s", "fr255sm", "fr265", "fr265s",
    "fr57042mm", "fr57047mm", "fr745", "fr945", "fr945lte", "fr955", "fr965", "fr970",
    # Fenix / Epix / Enduro
    "fenix6", "fenix6pro", "fenix6s", "fenix6spro", "fenix6xpro",
    "fenix7", "fenix7pro", "fenix7pronowifi", "fenix7s", "fenix7spro", "fenix7x", "fenix7xpro", "fenix7xpronowifi",
    "fenix843mm", "fenix847mm", "fenix8pro47mm", "fenix8solar47mm", "fenix8solar51mm",
    "fenix943mm", "fenix947mm", "fenix9pro43mm", "fenix9pro47mm", "fenix9pro51mm", "fenix9prosolar47mm", "fenix9prosolar51mm",
    "fenixe", "epix2", "epix2pro42mm", "epix2pro47mm", "epix2pro51mm", "enduro3",
    # Venu / Vivoactive
    "venu", "venu2", "venu2plus", "venu2s", "venu3", "venu3s", "venu441mm", "venu445mm", "venusq2", "venusq2m", "venux1",
    "vivoactive4", "vivoactive4s", "vivoactive5", "vivoactive6",
]


def get_ticket(username: str, password: str) -> str:
    s = requests.Session(impersonate="chrome")
    signin = f"{SSO}/signin?service={SERVICE}&clientId=CIQ_SDK_MANAGER&gauthHost={SSO}"
    headers = {"Referer": signin}
    html = s.get(signin, headers=headers, timeout=30)
    if html.status_code == 429:
        raise SystemExit("Garmin SSO: 429 Too Many Requests, reessayer plus tard ou depuis une autre IP")
    m = re.search(r'name="_csrf"\s+value="([^"]+)"', html.text)
    if not m:
        raise SystemExit(f"Page de login inattendue (HTTP {html.status_code}) : pas de _csrf")
    data = {"username": username, "password": password, "_csrf": m.group(1), "embed": "true"}
    r = s.post(signin, data=data, headers=headers, timeout=30)
    if r.status_code == 429:
        raise SystemExit("Garmin SSO: 429 Too Many Requests au POST, reessayer plus tard")
    m = re.search(r'ticket=([^"\\]+)', r.text)
    if not m:
        if "MFA" in r.text or "mfa" in r.text.lower():
            raise SystemExit("Le compte Garmin demande un code MFA : desactiver temporairement ou lancer en interactif")
        raise SystemExit(f"Login SSO refuse (HTTP {r.status_code})")
    return m.group(1)


def get_token(ticket: str) -> dict:
    data = {"grant_type": "service_ticket", "client_id": "CIQ_SDK_MANAGER", "service_ticket": ticket, "service_url": SERVICE}
    r = requests.post(f"{SGC}/api/oauth/token", data=data, impersonate="chrome", timeout=30)
    r.raise_for_status()
    return r.json()


def api(token: str, path: str, accept: str = "application/json") -> requests.Response:
    r = requests.get(f"{APIGCS}{path}", headers={"accept": accept, "authorization": f"Bearer {token}"}, impersonate="chrome", timeout=120)
    r.raise_for_status()
    return r


def install_devices(token: str, wanted: set[str] | None) -> list[str]:
    devices = api(token, "/ciq-product-onboarding/devices").json()
    root = CIQ_HOME / "Devices"
    root.mkdir(parents=True, exist_ok=True)
    done = []
    for d in devices:
        name = d["name"]
        if wanted is not None and name not in wanted:
            continue
        if not d.get("ciqInfoFileExists"):
            continue
        target = root / name
        if (target / "compiler.json").exists():
            done.append(name)
            continue
        print(f"  appareil {name} ({d.get('displayName')}) ...", flush=True)
        blob = api(token, f"/ciq-product-onboarding/devices/{d['partNumber']}/ciqInfo", accept="*/*").content
        zipfile.ZipFile(io.BytesIO(blob)).extractall(target)
        done.append(name)
    return done


def install_fonts(token: str) -> int:
    fonts = api(token, "/ciq-product-onboarding/fonts").json()
    root = CIQ_HOME / "Fonts"
    root.mkdir(parents=True, exist_ok=True)
    n = 0
    for f in fonts:
        cft = root / f"{f['name']}.cft"
        if cft.exists():
            continue
        blob = api(token, f"/ciq-product-onboarding/fonts/font?fontName={f['name']}", accept="*/*").content
        zipfile.ZipFile(io.BytesIO(blob)).extractall(root)
        n += 1
    return n


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("devices", nargs="*", help="identifiants d'appareils (fr965, fenix7...) ; defaut : liste integree")
    ap.add_argument("--all", action="store_true", help="tous les appareils")
    ap.add_argument("--list", action="store_true", help="liste les appareils disponibles et sort")
    ap.add_argument("--no-fonts", action="store_true")
    args = ap.parse_args()
    user, pw = os.environ.get("GARMIN_EMAIL"), os.environ.get("GARMIN_PASSWORD")
    if not user or not pw:
        raise SystemExit("GARMIN_EMAIL / GARMIN_PASSWORD manquants")
    print("Login SSO Garmin ...")
    token = get_token(get_ticket(user, pw))["access_token"]
    if args.list:
        for d in sorted(api(token, "/ciq-product-onboarding/devices").json(), key=lambda x: x["name"]):
            print(f"{d['name']:28} {d.get('displayName','')!s:40} {d.get('group','')} {'(a venir)' if d.get('upcoming') else ''}")
        return 0
    wanted = None if args.all else set(args.devices or DEFAULT_DEVICES)
    print(f"Appareils -> {CIQ_HOME / 'Devices'}")
    done = install_devices(token, wanted)
    print(f"  {len(done)} appareils presents : {', '.join(sorted(done))}")
    if not args.no_fonts:
        print(f"Polices -> {CIQ_HOME / 'Fonts'}")
        print(f"  {install_fonts(token)} polices telechargees")
    return 0


if __name__ == "__main__":
    sys.exit(main())
