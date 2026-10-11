#!/bin/bash
# start emulatora MysticalOS - wrapper dla GUI (Start-GUI.bat)
# jesli zmienisz miejsce obrazu, edytuj linie IMG= ponizej
IMG="${IMG:-/mnt/c/Users/Brajan/Downloads/port-release-dsu (1)/out/MysticalOS_0.6_DSU_nofooter.img}"
HERE="$(cd "$(dirname "$0")" && pwd)"

# AUDYT-fix: sudo musi dostac haslo TERAZ, w tym oknie (ma TTY). Bez tego
# faza 'fix obrazu' pada cicho przy starcie z GUI (sudo bez terminala = blad).
if ! sudo -v; then
  echo "!! Nie udalo sie zalogowac sudo (haslo). Odpal raz recznie w WSL:"
  echo "   bash $0"
  echo "Enter = zamknij okno..."; read -r _; exit 1
fi

# AUDYT-fix: zwykla rura zamiast 'exec > >(tee ...)' - process substitution
# w konsoli WSL bywal powodem pustego okna
bash "$HERE/../run-local-emu.sh" "$IMG" 2>&1 | tee "$HERE/gui-run.log"
RC=${PIPESTATUS[0]}
echo
echo "== zakonczono (kod $RC). Enter = zamknij okno..."
read -r _
exit $RC
