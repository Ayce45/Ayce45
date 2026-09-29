#!/usr/bin/env bash
# Compile l'app Connect IQ.
#   ./build.sh                 -> .prg fr965 (debug) dans bin/
#   ./build.sh -d venu3        -> .prg pour un autre appareil
#   ./build.sh --iq            -> paquet .iq (release, tous les appareils du manifest) pour sideload
#   ./build.sh --sim           -> variante simulateur (monkey-sim.jungle, reglages locaux)
# Prerequis : SDK dans ~/.Garmin/ConnectIQ/Sdks (voir docs/connectiq.md), cle keys/developer_key.der,
# appareils dans ~/.Garmin/ConnectIQ/Devices (python watch/tools/fetch_devices.py).
set -euo pipefail
cd "$(dirname "$0")"
SDK_DIR="${CIQ_SDK:-$(ls -d ~/.Garmin/ConnectIQ/Sdks/connectiq-sdk-* 2>/dev/null | sort | tail -1)}"
[ -n "$SDK_DIR" ] || { echo "SDK Connect IQ introuvable (CIQ_SDK ou ~/.Garmin/ConnectIQ/Sdks)"; exit 1; }
KEY="${CIQ_KEY:-keys/developer_key.der}"
[ -f "$KEY" ] || { echo "Cle developpeur absente: $KEY (voir docs/connectiq.md)"; exit 1; }
DEVICE=fr965; MODE=prg; JUNGLE=monkey.jungle; LEVEL=1
while [ $# -gt 0 ]; do
  case "$1" in
    -d) DEVICE="$2"; shift 2;;
    --iq) MODE=iq; shift;;
    --sim) JUNGLE=monkey-sim.jungle; shift;;
    -l) LEVEL="$2"; shift 2;;
    *) echo "option inconnue: $1"; exit 1;;
  esac
done
mkdir -p bin
export JAVA_TOOL_OPTIONS="${JAVA_TOOL_OPTIONS:-}"
if [ "$MODE" = iq ]; then
  OUT=bin/tgmuscu.iq
  "$SDK_DIR/bin/monkeyc" -e -f "$PWD/$JUNGLE" -o "$PWD/$OUT" -y "$PWD/$KEY" -r -l "$LEVEL" 2>&1 | grep -v "Picked up JAVA_TOOL_OPTIONS" || true
else
  SUFFIX=""; [ "$JUNGLE" = monkey-sim.jungle ] && SUFFIX="-sim"
  OUT="bin/tgmuscu${SUFFIX}-${DEVICE}.prg"
  "$SDK_DIR/bin/monkeyc" -d "$DEVICE" -f "$PWD/$JUNGLE" -o "$PWD/$OUT" -y "$PWD/$KEY" -l "$LEVEL" -w 2>&1 | grep -v "Picked up JAVA_TOOL_OPTIONS" || true
fi
ls -la "$OUT"
