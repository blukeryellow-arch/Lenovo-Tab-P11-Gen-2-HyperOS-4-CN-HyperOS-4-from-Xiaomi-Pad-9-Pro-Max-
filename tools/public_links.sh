#!/usr/bin/env bash
# public_links.sh - wgrywa plik na hostingi z BEZPOSREDNIM linkiem pobierania
# (klik = pobieranie, bez strony posredniej) i weryfikuje kazdy link probe'em
# HTTP (status + content-length). Uzycie (na runnerze, ma pelny internet):
#   bash tools/public_links.sh <sciezka-do-pliku> <plik-wyjsciowy-md>
#
# v2 (jeden-img): pokretla z env dla duzych plikow (super_mystical3.img 6,3 GB):
#   HOSTS='transferarch gofile bashupload'  - ktore hosty probowac (spacja-sep)
#   UP_MAX_TIME=7200                        - limit curl na upload (s), def. 900
#   STOP_AFTER=1                            - przerwij po pierwszym zweryfikowanym
# receipt 37058971097 (m3 krok 8): skrypt zniknal z drzewa -> "No such file
# or directory" (mirrory publiczne padaly milczaco). Odtworzony z ec33490.
set -uo pipefail
Z=$1; OUT=$2
: > "$OUT"
SZ=$(stat -c%s "$Z")
MT=${UP_MAX_TIME:-900}
HOSTS=${HOSTS:-"bashupload tempsh transferarch oshiat filebin litterbox72 gofile"}
echo "### Bezposrednie linki pobierania ($(basename "$Z"), $SZ B)" >> "$OUT"

has() { case " $HOSTS " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

up() {  # $1=nazwa, $2=komenda uploadu; zwraca 0 gdy link zweryfikowany (clen==SZ)
  local name=$1 cmd=$2 out url hdr code clen
  echo "=== $name ===" >&2
  out=$(eval "$cmd" 2>&1 || true)
  url=$(printf '%s' "$out" | grep -oE 'https://[^"[:space:]\\]+' | head -1)
  if [ -z "$url" ]; then
    { echo "## $name: UPLOAD NIEUDANY"; printf '%s\n' "$out" | head -3; echo; } >> "$OUT"
    echo "  $name: brak url" >&2
    return 1
  fi
  hdr=$(curl -sIL --max-time 60 "$url" 2>&1 || true)
  code=$(printf '%s' "$hdr" | grep -iE '^HTTP' | tail -1 | tr -d '\r')
  clen=$(printf '%s' "$hdr" | grep -i '^content-length' | tail -1 | tr -dc 0-9)
  {
    echo "## $name"
    echo "- link: $url"
    echo "- probe: ${code:-?} | content-length: ${clen:-?} (oczekiwane $SZ)"
    if [ "$clen" = "$SZ" ]; then echo "- **PLIK OD RAZU - klik = pobieranie**"; fi
    echo
  } >> "$OUT"
  echo "  $name -> $url (${code:-?}, len=${clen:-?})" >&2
  [ "$clen" = "$SZ" ]
}

BN=$(basename "$Z")
BIN="mysticalos-$(date +%s)"
SRV=""
if has gofile; then
  SRV=$(curl -sS --max-time 30 https://api.gofile.io/servers 2>/dev/null \
    | sed -n 's/.*"name":"\([^"]*\)".*/\1/p' | head -1)
  [ -n "$SRV" ] || { echo "## gofile: brak serwera z API" >> "$OUT"; echo "  gofile: brak serwera" >&2; }
fi

# name|komenda  (kolejnosc = preferencja)
SPECS=(
  "transferarch|curl -sS --max-time $MT -T '$Z' https://transfer.archivete.am/$BN"
  "gofile|curl -sS --max-time $MT -F file=@'$Z' https://${SRV}.gofile.io/contents/uploadfile"
  "bashupload|curl -sS --max-time $MT -T '$Z' https://bashupload.com/$BN"
  "tempsh|curl -sS --max-time $MT -T '$Z' https://temp.sh/$BN"
  "oshiat|curl -sS --max-time $MT -T '$Z' 'https://oshi.at/?expire=259200'"
  "filebin|curl -sS --max-time $MT -X POST -F 'file=@$Z' https://filebin.net/$BIN/$BN"
  "litterbox72|curl -sS --max-time $MT -F reqtype=fileupload -F time=72h -F fileToUpload=@'$Z' https://litterbox.catbox.moe/resources/internals/api.php"
)
for spec in "${SPECS[@]}"; do
  name=${spec%%|*}; cmd=${spec#*|}
  has "$name" || continue
  if [ "$name" = "gofile" ] && [ -z "$SRV" ]; then continue; fi
  if up "$name" "$cmd"; then
    if [ "${STOP_AFTER:-0}" = "1" ]; then
      echo "STOP_AFTER=1: $name wystarczy - koncze" >&2
      break
    fi
  fi
done

echo "--- raport ---" >&2
cat "$OUT" >&2
