#!/usr/bin/env bash
# Triage po flashu: czytamy logcat i mowimy, CO STANELO - zamiast zostawiac
# uzytkownika z 'nie bootuje'. Powstal w noc 24/25 IX razem z wariantem coherent
# (docs/09), bo lista podejrzanych jest znana Z GORY: to wszystko, czego system
# A17 moze wymagac od vendora A12 (VNDK 31, composer HIDL 2.1, brak AIDL HAL-i).
#
# Uzycie:
#   adb wait-for-device; adb logcat -b all -d > logcat.txt
#   bash tools/postflash_triage.sh logcat.txt        # plik
#   bash tools/postflash_triage.sh --live            # prosto z adb (logcat -d)
#
# Wyjscie: raport per podsystem + WERDYKT (ktery stoper jest pierwszy na liscie
# przyczyn). rc=0 boot wyglada zdrowo (albo log za krotki - patrz ostrzezenia),
# rc=1 znaleziono stoper, rc=2 zle wywolanie.
set -uo pipefail

if [ $# -eq 0 ] || [ -z "$1" ]; then
  echo "uzycie: $0 <plik-logcat> | --live" >&2; exit 2
fi

TMP=$(mktemp /tmp/triage.XXXXXX.log)
trap 'rm -f "$TMP"' EXIT
if [ "$1" = "--live" ]; then
  command -v adb >/dev/null || { echo "brak adb w PATH" >&2; exit 2; }
  adb logcat -b all -d > "$TMP" || { echo "adb logcat nie wyszedl" >&2; exit 2; }
else
  [ -f "$1" ] || { echo "nie ma pliku: $1" >&2; exit 2; }
  cp "$1" "$TMP"
fi
LOG="$TMP"
LINES=$(wc -l < "$LOG")
echo "== triage: $1 ($LINES linii)"
if [ "$LINES" -lt 200 ]; then
  echo "   UWAGA: log krotki ($LINES linii) - jesli tablet dopiero bootuje, odczekaj i powtorz."
fi

# licznik stoperow: kazdy podsystem moze podbic wlasny licznik dowodow
declare -A N
evidence() { # evidence <podsystem> <opis> <regexp>
  local sys=$1 desc=$2 pat=$3
  local hits
  hits=$(grep -cE "$pat" "$LOG" || true)
  if [ "${hits:-0}" -gt 0 ]; then
    N[$sys]=$(( ${N[$sys]:-0} + hits ))
    printf '   [%s] %s — %s trafien\n' "$sys" "$desc" "$hits"
    grep -m2 -E "$pat" "$LOG" | sed 's/^/        | /' | cut -c1-160
  fi
}

echo ""
echo "== podsystemy"
evidence VINTF   "bramka VINTF (macierz nie przeszla)"            'Failed to initialize VINTF|vintf.*not compatible|Compatibility.*DENIED'
evidence MOUNT   "montowanie partycji (EROFS/ext4/dm)"            'Unable to mount|mount.*failed.*(system|product|ext|erofs)|dm-.*verity.*(error|corrupt)|fs_mgr.*mount failed'
evidence AVB     "weryfikacja AVB (vbmeta/hashtree)"              'avb.*(vbmeta|hashtree).*(fail|error|mismatch)|Verification failed'
evidence APEX    "apexd (podstawowe pakiety A17 na kernelu 5.10)" 'apexd.*([Ff]ail|error)|apex.*(mount|activate).*fail|Failed to activate'
evidence ZYGOTE  "Zygote / system_server"                          'Zygote.*(fatal|Fatal|abort)|System server.*[Ff]atal|FATAL EXCEPTION.*system_server|SystemServer.*wtf.*loop'
evidence SF      "SurfaceFlinger / composer (HIDL 2.1)"            "surfaceflinger.*(fatal|FATAL|abort|crash)|composer.*(died|crash|not available|getService.*fail)|graphics\.composer.*[Ff]ail"
evidence HAL     "brakujace HAL-e (AIDL z A13+ na vendorze A12)"   "Wait for service .* timed out|getService.*failed|Could not find service|service .* not published|hwservicemanager.*not found"
evidence AUDIO   "audio (HIDL audio@7 vs A17 framework)"           'audio@|android\.hardware\.audio.*(fail|died|crash)'
evidence CRYPT   "szyfrowanie / vold / f2fs"                       'vold.*(error|fail)|f2fs.*error|metadata encryption.*fail|Failed to unlock'
evidence WATCHDOG "watchdog / reboot loop"                         'WATCHDOG.*killed|sysrq.*[Rr]eboot|Restarting system with command'
evidence BOOTED  "sygnaly ukonczonego bootu (dobra wiadomosc)"     'Boot completed|sys.boot_completed=1|Displayed.*com\.android\.systemui'

echo ""
echo "== synteza"
declare -i STOPERS=0
for s in VINTF MOUNT AVB APEX ZYGOTE SF HAL AUDIO CRYPT WATCHDOG; do
  if [ "${N[$s]:-0}" -gt 0 ]; then STOPERS+=1; fi
done
BOOTED_N=${N[BOOTED]:-0}

if [ "$BOOTED_N" -gt 0 ] && [ "$STOPERS" -eq 0 ]; then
  echo "WERDYKT: boot UKONCZONY i bez stoperow w logu."
  echo "  nastepny krok: sprawdz dzialajace podsystemy (kamera/audio/wifi) i log dalej."
  exit 0
fi
if [ "$STOPERS" -eq 0 ]; then
  echo "WERDYKT: brak stoperow w tym logu (i brak sygnalu ukonczonego bootu)."
  echo "  jesli tablet stoi: doloz pelny log od startu (logcat -b all) i retry."
  exit 0
fi
echo "WERDYKT: stoperow: $STOPERS. Najbardziej prawdopodobna przyczyna (wg kolejnosci startu):"
if [ "${N[VINTF]:-0}" -gt 0 ]; then
  echo "  1. VINTF — macierz poziomu nie przeszla. To zaskoczenie (wariant miekki ma otwierac"
  echo "     bramke) — sprawdz czy flashowany system to ten z tego wydania (suma w SHA256SUMS)."
elif [ "${N[MOUNT]:-0}" -gt 0 ]; then
  echo "  1. MONTOWANIE — obraz/partycja nie wstaje (EROFS? rozmiar slotu?). Sprawdz linie"
  echo "     'fs_mgr' w logu; porownaj z device-probe.sh (CONFIG_EROFS_FS_LZ4)."
elif [ "${N[APEX]:-0}" -gt 0 ]; then
  echo "  1. APEXD — pakiety A17 nie aktywuja sie na kernelu 5.10/GKI. To luka A17->A12:"
  echo "     sciezka B' ma prawo tu stanac i NIE da sie jej naprawic bez nowszego kernela."
elif [ "${N[SF]:-0}" -gt 0 ]; then
  echo "  1. SURFACEFLINGER/COMPOSER — framework A17 nie dogadal sie z composerem HIDL 2.1"
  echo "     vendora A12. Pulpit nie wstanie w tym ukladzie; sensowne dalsze kroki: wariant"
  echo "     lekki (ten sam problem mozliwy) albo GSI/rownowazony system blizszy A12."
elif [ "${N[ZYGOTE]:-0}" -gt 0 ]; then
  echo "  1. ZYGOTE/SYSTEM_SERVER — framework pada przy starcie. Poszukaj w logu pierwszego"
  echo "     'FATAL EXCEPTION' i jego pakietu — to wskaze, jakiego HAL-a/klasy brakuje."
elif [ "${N[HAL]:-0}" -gt 0 ]; then
  echo "  1. HAL-E — framework czeka na uslugi, ktorych vendor A12 nie ma (AIDL z A13+)."
  echo "     Nazwy serwisow z linii 'Wait for service' = lista brakow; czesc da sie obejsc"
  echo "     wariantem miekkim macierzy, czesc nie."
elif [ "${N[AUDIO]:-0}" -gt 0 ]; then
  echo "  1. AUDIO — HIDL audio@7.x niedostepny dla A17. Tablet moze bootowac bez dzwieku."
else
  echo "  1. patrz podsystemy z dowodami wyzej (CRYPT/WATCHDOG) — szczegoly w liniach pod"
  echo "     naglowkami."
fi
echo ""
echo "  ten raport wklej do rozmowy z agentem — kontynuacja diagnostyki na jego podstawie."
exit 1
