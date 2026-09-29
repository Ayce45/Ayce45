#!/usr/bin/env bash
# Lance le simulateur (avec Xvfb si aucun DISPLAY) puis charge le .prg simulateur.
#   ./run-sim.sh [device]        (defaut fr965 ; le .prg doit exister, voir build.sh --sim)
set -euo pipefail
cd "$(dirname "$0")"
DEVICE="${1:-fr965}"
SDK_DIR="${CIQ_SDK:-$(ls -d ~/.Garmin/ConnectIQ/Sdks/connectiq-sdk-* 2>/dev/null | sort | tail -1)}"
PRG="$PWD/bin/tgmuscu-sim-${DEVICE}.prg"
[ -f "$PRG" ] || PRG="$PWD/bin/tgmuscu-${DEVICE}.prg"
[ -f "$PRG" ] || { echo "Compiler d'abord: ./build.sh --sim -d $DEVICE"; exit 1; }
# Libs webkit2gtk 4.0 (Ubuntu 22.04) extraites pour Ubuntu 24.04 : voir docs/connectiq.md
export LD_LIBRARY_PATH="${CIQ_COMPAT_LIBS:-/usr/local/lib/ciq-compat}:${LD_LIBRARY_PATH:-}"
if [ -z "${DISPLAY:-}" ]; then
  export DISPLAY=:99
  pgrep -x Xvfb >/dev/null || (Xvfb :99 -screen 0 1280x900x24 >/dev/null 2>&1 &)
  sleep 1
fi
pgrep -x simulator >/dev/null || ("$SDK_DIR/bin/simulator" >/tmp/ciq-simulator.log 2>&1 &)
sleep 6
exec "$SDK_DIR/bin/monkeydo" "$PRG" "$DEVICE"
