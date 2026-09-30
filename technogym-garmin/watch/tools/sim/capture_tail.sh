#!/bin/bash
# Pilotage du simulateur Connect IQ (fr955) sous Xvfb :99 avec xdotool, captures h_*.png dans $OUT.
# Prerequis : simulateur lance (SDK_DIR/bin/simulator &), backend .venv, Xvfb :99, xdotool, imagemagick.
# Usage : watch/tools/sim/<script>.sh [dossier de sortie]
# Repères (fenetre 446x595) : START (357,232), BACK (357,385), UP (25,300), DOWN (40,385) ; appui long UP = touche
# clavier "Menu" (la premiere touche apres un changement de vue est perdue, d'ou deux appuis) ; un clic sur l'ecran
# vaut START et donne le focus clavier. Le simulateur garde stockage et reglages dans
# /tmp/com.garmin.connectiq/GARMIN/APPS/{DATA,SETTINGS} : les supprimer pour repartir a zero.
REPO=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$REPO"
OUT=${1:-/tmp/spotter-captures}; mkdir -p "$OUT"
export DISPLAY=:99 LD_LIBRARY_PATH=/usr/local/lib/ciq-compat
S=$OUT
SDK_DIR=$(ls -d ~/.Garmin/ConnectIQ/Sdks/connectiq-sdk-* | sort | tail -1)
UP() { xdotool mousemove 25 300 click 1; sleep ${1:-0.5}; }
DOWN() { xdotool mousemove 40 385 click 1; sleep ${1:-0.5}; }
START() { xdotool mousemove 357 232 click 1; sleep ${1:-1.5}; }
BACK() { xdotool mousemove 357 385 click 1; sleep ${1:-1.5}; }
MENU() { sleep 1; xdotool key Menu; sleep 2; xdotool key Menu; sleep 2; }
SHOT() { import -window root $S/h_$1.png; }
for p in $(pgrep -f "run.py"); do [ "$p" != "$$" ] && [ "$p" != "$PPID" ] && kill "$p"; done; sleep 1
(LIVE_REPLAY_PATH=$REPO/scratch/poc_live_log.jsonl LIVE_REPLAY_STEP=6 nohup .venv/bin/python run.py > /tmp/backend.log 2>&1 &)
("$SDK_DIR/bin/monkeydo" "$REPO/watch/bin/spotter-sim-fr955.prg" fr955 > /tmp/monkeydo.log 2>&1 &); sleep 14
xdotool mousemove 200 300 click 1; sleep 45; SHOT t_page0
# une serie libre rapide pour avoir du volume dans le resume : Chest press, 2 reps
START 2.2; DOWN 0.4; DOWN 0.4; DOWN 0.4; DOWN 1.2; START 2.5; DOWN 1.2; START 2.5; START 0.8; START 1.2; START 2
UP 0.3; UP 0.3; START 2.5; START 1.5; MENU; UP 1.2; START 1.5          # serie faite, passer le repos, menu > Retour
SHOT t_live
MENU; SHOT livemenu; UP 1.2; UP 1.5; SHOT livemenu2; START 2.5; SHOT summary
MENU; SHOT summenu; BACK; SHOT summary2; START 2.5; SHOT saved
MENU; SHOT homemenu; BACK 1
grep -i "error\|exception\|unhandled" /tmp/monkeydo.log | grep -v JAVA_TOOL | tail -3 | cut -c1-220
cd $S && for f in h_t_page0 h_t_live h_livemenu h_livemenu2 h_summary h_summenu h_summary2 h_saved h_homemenu; do convert $f.png -crop 320x320+40+150 +repage -resize 60% c_$f.png; done
montage -label '%f' c_h_t_page0.png c_h_t_live.png c_h_livemenu.png c_h_livemenu2.png c_h_summary.png c_h_summenu.png c_h_summary2.png c_h_saved.png c_h_homemenu.png -tile 5x2 -geometry +4+4 -background '#222' -fill white tileE.png
echo ok
