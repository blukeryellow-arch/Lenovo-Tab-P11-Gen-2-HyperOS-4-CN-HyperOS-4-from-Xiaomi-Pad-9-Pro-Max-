#!/bin/bash
# start emulatora MysticalOS - wrapper dla GUI (Start-GUI.bat)
# jesli zmienisz miejsce obrazu, edytuj linie IMG= ponizej
IMG="${IMG:-/mnt/c/Users/Brajan/Downloads/port-release-dsu (1)/out/MysticalOS_0.5_DSU_nofooter.img}"
HERE="$(cd "$(dirname "$0")" && pwd)"
# caly output do okna ORAZ do gui-run.log (GUI pokazuje fazy zanim powstanie console.log)
exec > >(tee "$HERE/gui-run.log") 2>&1
bash "$HERE/../run-local-emu.sh" "$IMG"
RC=$?
echo
echo "== zakonczono (kod $RC). Enter = zamknij okno..."
read -r _
exit $RC
