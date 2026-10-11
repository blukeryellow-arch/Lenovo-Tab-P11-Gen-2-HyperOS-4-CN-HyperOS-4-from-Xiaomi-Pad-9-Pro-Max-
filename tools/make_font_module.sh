#!/usr/bin/env bash
# Generator modulu Magisk/KernelSU z FONTAMI HyperOS dla Lenovo Tab P11 Gen 2 (TB350FU).
#
# Czemu akurat fonty, a nie RRO - zmierzone w tej sesji (2026-09-23):
#   * /system/fonts HyperOS 4 to w przewaznej liczbie SYMLINKI do /product/fonts/*.ttf
#     (np. './system/fonts/MiSansLatinVF.ttf -> /product/fonts/MiSansLatinVF.ttf'),
#     wiec realne bajty siedza w image 'product' (6,45 GB) - nie w 'system'.
#   * RRO HyperOS sa podpisane kluczem MIUI (sha256 certyfikatu c9009d01...,
#     a auto_generated_rro d45f076f...) - NIE AOSP testkeyem. Android 11+ odrzuca
#     RRO ktorego podpis nie zgadza sie z pakietem nakladanym, a framework targetu
#     (GSI A14) zyje kluczem AOSP. Dlatego nakladki wymagalyby przepodpisania (aap2 +
#     apksigner + JRE), a FONTY nie wymagaja zadnego podpisu - sa plikami.
# Stad ten skrypt: dostarcza to, co dziala bez podpisu i bez ruszania AVB.
#
# Uzycie:
#   tools/make_font_module.sh --fonts KATALOG_Z_TTFAMI --out MODUL \
#       [--family "MiSans"] [--primary MiSansLatinVF.ttf] [--name "HyperOS 4 fonts"]
# KATALOG to /product/fonts ze HyperOS (albo /system/fonts - wtedy wezmie co jest).
#
# Skrypt NIE dotyka urzadzenia i NIE klamie: na koncu weryfikuje (a) kazdy font magic
# bajtami TTF/OTF/TTC, (b) fonts.xml parsuje, (c) kazde <file> wskazuje na plik, ktory
# realnie jest w module. Jezeli ktorys punkt padnie - rc != 0 i mowi ktory.
set -uo pipefail

FONTS="" OUT="" FAMILY="MiSans" PRIMARY="" MODNAME="HyperOS 4 fonts" MAXF=48
while [ $# -gt 0 ]; do
  case "$1" in
    --fonts) FONTS=$2; shift 2;;
    --out) OUT=$2; shift 2;;
    --family) FAMILY=$2; shift 2;;
    --primary) PRIMARY=$2; shift 2;;
    --name) MODNAME=$2; shift 2;;
    --max-fonts) MAXF=$2; shift 2;;
    *) echo "nieznany argument: $1" >&2; exit 2;;
  esac
done
[ -n "$FONTS" ] && [ -d "$FONTS" ] || { echo "--fonts KATALOG (istniejacy) wymagany" >&2; exit 2; }
[ -n "$OUT" ] || { echo "--out KATALOG_DOC (modul) wymagany" >&2; exit 2; }

ver() { echo "  $*" >&2; }
echo "== make_font_module: $FONTS -> $OUT =="
mkdir -p "$OUT/system/product/fonts" "$OUT/system/fonts" "$OUT/common" 2>/dev/null

# --- 1./2. dobor fontow (po sygnaturze) + generowanie fonts.xml ----------------
# Cal ta logika jest w tools/fontgen.py - w bashu by sie nie obronila, a zagniezdzone
# heredocy '<<PY' wewnatrz '<<PY' ucinaly skrypt PO CICHU (zmierzone 2026-09-23).
python3 tools/fontgen.py --fonts "$FONTS" --out "$OUT" --family "$FAMILY" \
  ${PRIMARY:+--primary "$PRIMARY"} --max-fonts "$MAXF"
rc=$?
[ $rc -eq 0 ] || { echo "FATAL: fontgen.py rc=$rc - nie mam z czego zrobic modulu"; exit $rc; }

# --- 3. module.prop + skrypty modulu -----------------------------------------
VC=$(date -u +%Y%m%d%H)
cat > "$OUT/module.prop" <<PROP
id=hyperos4_fonts_p11g2
name=$MODNAME
version=HyperOS4-fonts-$(date -u +%Y-%m-%dT%H%M)Z ($VC)
versionCode=$VC
author=arena-agent (pomiar na plikach usera)
description=Rodzina $FAMILY z HyperOS 4 (Xiaomi Pad 9 Pro Max) na Lenovo Tab P11 Gen 2. Bez RRO i bez AVB - pliki, wiec zadny podpis nie jest wymagany (RRO Xiaomi sa podpisane kluczem MIUI c9009d01... i na frameworkie GSI odpada). Fonty sa skopiowane z /product/fonts, bo w /system/fonts to tylko symlinki.
PROP
cat > "$OUT/customize.sh" <<'CUST'
#!/system/bin/sh
# Walidacja PRZED mountem - jesli /product nie istnieje (inne SKU), pliki i tak wejde
# do /system/fonts, wiec nie przerywamy; raportujemy tylko.
UI_print "HyperOS4 fonts: module=hyperos4_fonts_p11g2"
if [ ! -d /product ]; then
  UI_print "  /product nie istnieje - fonts.xml i tak wskaze na /system/fonts"
fi
n=$(ls "$MODPATH/system/product/fonts" 2>/dev/null | wc -w)
UI_print "  plikow font w module: $n"
[ "$n" -gt 0 ] || abort "modul bez plikow .ttf - nie mam czego podmienic"
CUST
cat > "$OUT/uninstall.sh" <<'UN'
#!/system/bin/sh
# nic nie ruszamy poza /data - modulu nie ma w /system, Magisk sam odmontuje
UN
printf 'HyperOS 4 fonts module - wygenerowane %s\n' "$(date -u +%FT%TZ)" > "$OUT/README-module.txt"
echo "  plikow w module: $(find "$OUT" -type f | wc -l), rozmiar: $(du -sh "$OUT" | cut -f1)"

# --- 4. walidacja koncowa ------------------------------------------------------
python3 - "$OUT" <<'PY'
import os, sys, xml.etree.ElementTree as ET, re
out = sys.argv[1]
bad = 0
# (a) fonts.xml parsuje
p = os.path.join(out, 'system/etc/fonts.xml')
try:
    root = ET.parse(p).getroot()
except Exception as e:
    print(f"  BLAD: fonts.xml nie parsuje sie: {e}"); sys.exit(5)
if root.tag != 'familyset':
    print(f"  BLAD: korzen to <{root.tag}>, a ma byc <familyset>"); sys.exit(5)
# (b) kazde <file>/<font> istnieje
refs = [f.text.strip() for f in root.iter('font') if f.text and f.text.strip()]
refs += [f.text.strip() for f in root.iter('file') if f.text and f.text.strip()]
if not refs:
    print("  BLAD: fonts.xml nie wskazuje ZADNEGO pliku"); sys.exit(6)
for r in sorted(set(refs)):
    ok = any(os.path.isfile(os.path.join(out, 'system', d, r)) for d in ('product/fonts', 'fonts'))
    if not ok:
        print(f"  BLAD: <font>{r}</font> nie ma pliku w module"); bad += 1
# (c) kazdy plik w module ma magie fontu
MAGIC = (b'\x00\x01\x00\x00', b'OTTO', b'ttcf', b'true')
n = 0
for dirpath, _, files in os.walk(os.path.join(out, 'system')):
    for f in files:
        if not re.search(r'\.(ttf|otf|ttc)$', f, re.I):
            continue
        fp = os.path.join(dirpath, f); n += 1
        head = open(fp, 'rb').read(4)
        if head not in MAGIC:
            print(f"  BLAD: {f} ma bajty startowe {head!r} - to nie font"); bad += 1
        if os.path.getsize(fp) < 1024:
            print(f"  BLAD: {f} ma tylko {os.path.getsize(fp)} B"); bad += 1
print(f"  weryfikacja: {len(set(refs))} referencji w fonts.xml, {n} plikow font, bledow: {bad}")
sys.exit(7 if bad or not n else 0)
PY
rc=$?
if [ $rc -eq 0 ]; then
  ( cd "$OUT" && find . -type f ! -name SHA256SUMS.txt -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS.txt )
  echo "== OK: modul gotowy w $OUT (sumy w SHA256SUMS.txt) =="
  echo "   instalacja: adb push $OUT/. /data/adb/modules/.  (albo zip przez Magisk)"
  echo "   uwaga: przed pushem 'magisk --install-module' wymaga zipa - tools/pack_module.sh"
  echo "   usuwanie: Magisk -> Moduly -> HyperOS 4 fonts, albo rm -rf /data/adb/modules/hyperos4_fonts_p11g2 && adb reboot"
else
  echo "== WALIDACJA PADLA (rc=$rc) - modulu NIE nalezy instalowac ==" >&2
fi
exit $rc
