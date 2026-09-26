#!/usr/bin/env bash
# Wgrywa HyperOS4_P11Gen2.zip na kilka hostow z BEZPOSREDNIM linkiem pobierania
# (klik = pobieranie, bez strony posredniej) i weryfikuje kazdy link probe'em
# HTTP (status + content-length). Uzycie (na runnerze, ma pelny internet):
#   bash tools/public_links.sh <sciezka-do-zipa> <plik-wyjsciowy-md>
set -uo pipefail
Z=$1; OUT=$2
: > "$OUT"
SZ=$(stat -c%s "$Z")
echo "### Bezposrednie linki pobierania (zip $SZ B, sha w release)" >> "$OUT"

up() {  # $1=nazwa, $2=komenda uploadu
  local name=$1 cmd=$2 out url hdr code clen
  echo "=== $name ===" >&2
  out=$(eval "$cmd" 2>&1 || true)
  url=$(printf '%s' "$out" | grep -oE 'https://[^"[:space:]\\]+' | head -1)
  if [ -z "$url" ]; then
    { echo "## $name: UPLOAD NIEUDANY"; printf '%s\n' "$out" | head -3; echo; } >> "$OUT"
    echo "  $name: brak url" >&2
    return
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
}

up bashupload  "curl -sS --max-time 900 -T '$Z' https://bashupload.com/HyperOS4_P11Gen2.zip"
up tempsh      "curl -sS --max-time 900 -T '$Z' https://temp.sh/HyperOS4_P11Gen2.zip"
up litterbox72 "curl -sS --max-time 900 -F reqtype=fileupload -F time=72h -F fileToUpload=@'$Z' https://litterbox.catbox.moe/resources/internals/api.php"
SRV=$(curl -sS --max-time 30 https://api.gofile.io/servers | sed -n 's/.*"name":"\([^"]*\)".*/\1/p' | head -1)
if [ -n "${SRV:-}" ]; then
  up gofile "curl -sS --max-time 900 -F file=@'$Z' https://${SRV}.gofile.io/contents/uploadfile"
else
  echo "## gofile: brak serwera z API" >> "$OUT"
fi

echo "--- raport ---" >&2
cat "$OUT" >&2
