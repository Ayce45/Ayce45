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
MENU() { sleep 1; xdotool key Menu; sleep 2; xdotool key Menu; sleep 2; }   # la premiere touche apres un changement de vue est perdue, la seconde est sans effet sur un menu ouvert
KDOWN() { xdotool key Down; sleep ${1:-0.8}; }
KUP() { xdotool key Up; sleep ${1:-0.8}; }
SHOT() { import -window root $S/h_$1.png; }
for p in $(pgrep -f "run.py"); do [ "$p" != "$$" ] && [ "$p" != "$PPID" ] && kill "$p"; done; sleep 1
(LIVE_REPLAY_PATH=$REPO/scratch/poc_live_log.jsonl LIVE_REPLAY_STEP=6 nohup .venv/bin/python run.py > /tmp/backend.log 2>&1 &)
xdotool mousemove 18 12 click 1; sleep 1; xdotool mousemove 91 312 click 1; sleep 2; xdotool key Return; sleep 3
("$SDK_DIR/bin/monkeydo" "$REPO/watch/bin/spotter-sim-fr955.prg" fr955 > /tmp/monkeydo.log 2>&1 &); sleep 14
SHOT home
xdotool mousemove 200 300 click 1; sleep 45; SHOT page0     # START (tap : donne aussi le focus clavier)
DOWN 1.2; SHOT page1; DOWN 1.2; SHOT page2; DOWN 1.2
START 2.2; SHOT actions; DOWN 0.4; DOWN 0.4; DOWN 0.4; DOWN 1.2; SHOT actions_list; START 2.5; DOWN 1.2; SHOT list
START 2.5; SHOT detail_img; DOWN 2; SHOT detail_equip; DOWN 2; SHOT detail_muscles
START 0.8; SHOT page0_chest; START 1.2; SHOT actions2; START 2; SHOT set
DOWN 0.8; MENU; SHOT setmenu; START; SHOT weight; UP 0.4; UP 1; SHOT weight2; START; SHOT set_w
UP 0.3; UP 0.3; SHOT set_reps; START 2.5; SHOT rest; sleep 25; SHOT rest2; sleep 35; SHOT set2
MENU; SHOT setmenu2; UP 1.2; START; SHOT set_back      # Retour
SHOT after_back
MENU; SHOT livemenu; UP 1.2; UP 1.5; SHOT livemenu2; START 2.5; SHOT summary
MENU; SHOT summenu; BACK; SHOT summary2; START 2.5; SHOT saved
MENU; SHOT homemenu; BACK 1
grep -i "error\|exception\|unhandled" /tmp/monkeydo.log | grep -v JAVA_TOOL | tail -3 | cut -c1-220
cd $S && for f in h_*.png; do convert $f -crop 320x320+40+150 +repage -resize 60% c_$f; done
montage -label '%f' c_h_home.png c_h_page0.png c_h_page1.png c_h_page2.png c_h_actions.png c_h_actions_list.png c_h_list.png c_h_detail_img.png -tile 4x2 -geometry +4+4 -background '#222' -fill white tileA.png
montage -label '%f' c_h_detail_equip.png c_h_detail_muscles.png c_h_page0_chest.png c_h_actions2.png c_h_set.png c_h_setmenu.png c_h_weight.png c_h_weight2.png -tile 4x2 -geometry +4+4 -background '#222' -fill white tileB.png
montage -label '%f' c_h_set_w.png c_h_set_reps.png c_h_rest.png c_h_rest2.png c_h_set2.png c_h_setmenu2.png c_h_set_back.png c_h_after_back.png -tile 4x2 -geometry +4+4 -background '#222' -fill white tileC.png
montage -label '%f' c_h_livemenu.png c_h_livemenu2.png c_h_summary.png c_h_summenu.png c_h_summary2.png c_h_saved.png c_h_homemenu.png -tile 4x2 -geometry +4+4 -background '#222' -fill white tileD.png
echo ok
