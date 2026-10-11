#!/bin/bash
# start emulatora MysticalOS - wrapper dla GUI (Start-GUI.bat)
# jesli zmienisz miejsce obrazu, edytuj linie IMG= ponizej
IMG="${IMG:-/mnt/c/Users/Brajan/Downloads/port-release-dsu (1)/out/MysticalOS_0.5_DSU_nofooter.img}"
HERE="$(cd "$(dirname "$0")" && pwd)"
exec bash "$HERE/../run-local-emu.sh" "$IMG"
