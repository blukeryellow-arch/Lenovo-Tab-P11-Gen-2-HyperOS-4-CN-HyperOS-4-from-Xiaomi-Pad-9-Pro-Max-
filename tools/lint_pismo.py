#!/usr/bin/env python3
"""Lint pisma: nie pozwala, zeby do wydania weszly znaki w pismie obcym wobec jezyka dokumentacji.

Po co to istnieje (a nie jest kaprysem estetycznym): w tym repo trzy razy pojawily sie
znaky CJK wtracone mimowolnie - `\u62ff` w docs/06, `\u5916\u90e8` w scripts/build_overlay_apk.sh i
`\u4e0b\u6e38` w .github/workflows/release-selftest.yml. Zaden z nich nie byl zamiarem; kazdy
przeszedl, bo pierwsza wersja skanera uzywala glob('**/*'), ktory NIE WCHODZI do
katalogow zaczynajacych sie od kropki - czyli .github/ byl caly slepy. Stad dwie reguly
wyszyte z tego kodu:

  1. zrodlem listy plikow jest `git ls-files` (to, co realnie trafia do wydania),
     nie glob - dzieki temu `.github/`, `.gitignore` sa skanowane;
  2. pliki binarne (obrazy .img, apk) sa pomijane swiadomie i to jest ZAPISANE w
     wyniku, zeby 'czysto' nie znaczylo 'nie zajrzalem'.

Dopuszczalne: pismo lacinskie (w tym polskie diakryty), cyfry, interpunkcja, emoji
naglowkowe? - NIE, emoji tez sa wykluczone: ten projekt jest w jezyku polskim z
nazewnictwem angielskim i nic wiecej tu nie ma byc.
"""
import os
import re
import subprocess
import sys

# przedzialy, ktore w tym repo sa bledem, nie trescia
BANNED = {
    "CJK (hanzi/kana/hangul/katakana + pelnoszerokosc)": r"[\u3000-\u30ff\u31f0-\u31ff\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff\uac00-\ud7af\uff00-\uffef]",
    "cyrylica": r"[\u0400-\u04ff]",
    "greka": r"[\u0370-\u03ff]",
    "hebrajski": r"[\u0590-\u05ff]",
    "arabski": r"[\u0600-\u06ff]",
    "emoji/piktogramy": r"[\U0001f000-\U0001faff\u2600-\u27bf]",
}
MAX_BYTES = 4_000_000

# Wyjatek ZAPISANY, nie milczacy: w plikach Markdown zezwalamy na cztery znaki
# stosowane w tabelach jako stan kontroli. Nie na 'dowolne emoji' i NIE w kodzie -
# w .sh/.py/.yml/.tsv/.txt obowiazuje pelny zakaz, bo to wlasnie tam obce znaki
# wpadaly (patrz docstring). Zezwolenie jest zawezone co do pliku i co do znaku.
MD_ALLOWED = set("\u2713\u2717\u2705\u274c")   # to sa WYŁĄCZNIE te cztery, nie "jakiekolwiek emoji"
MD_SUFFIXES = (".md",)


def tracked_files():
    out = subprocess.run(["git", "ls-files", "-z"], capture_output=True, text=True)
    if out.returncode != 0:
        sys.exit(f"FATAL: git ls-files nie wyszlo: {out.stderr.strip()[:200]}")
    return [f for f in out.stdout.split("\0") if f]


def main(argv):
    root = "."
    quiet = "--quiet" in argv
    args = [a for a in argv if not a.startswith("--")]
    if args:
        root = args[0]
    files = tracked_files()
    scanned = skipped_bin = skipped_big = 0
    hits = []
    for rel in files:
        f = os.path.join(root, rel) if root != "." else rel
        if not os.path.isfile(f):
            continue                      # usuniety z dysku, ale jeszcze w indeksie
        if os.path.getsize(f) > MAX_BYTES:
            skipped_big += 1
            continue
        try:
            with open(f, encoding="utf-8") as fh:
                text = fh.read()
        except (UnicodeDecodeError, OSError):
            skipped_bin += 1              # obrazy .img, .apk, .ttf - tu nie ma pisma
            continue
        scanned += 1
        if rel.endswith(MD_SUFFIXES):
            # wyciagnac TYLKO dozwolone znaki, nie 'przymknac oko na caly plik'
            text = "".join(c for c in text if c not in MD_ALLOWED)
            allowed_used = sum(1 for c in "".join(open(f, encoding="utf-8").read()) if c in MD_ALLOWED)
        for name, pat in BANNED.items():
            found = sorted(set(re.findall(pat, text)))
            if found:
                for ln, line in enumerate(text.split("\n"), 1):
                    if re.search(pat, line):
                        hits.append((rel, ln, name, line.strip()[:100]))
                        break
                hits.append((rel, 0, name + " [wystepuje]", " ".join(found[:8])))
    if not quiet:
        print(f"skan pisma: {scanned} plikow tekstowych, "
              f"{skipped_bin} binarnych (pominiete), {skipped_big} powyzej {MAX_BYTES//10**6} MB")
    if hits:
        seen = set()
        for rel, ln, name, ctx in hits:
            key = (rel, name)
            if key in seen:
                continue
            seen.add(key)
            print(f"  {rel}" + (f":{ln}" if ln else "") + f": {name}")
            print(f"      {ctx}")
        print(f"BRUDNYCH PIOR: {len(seen)} - to NIE jest styl do poprawienia 'potem'")
        return 1
    if not quiet:
        print("  czysto: zadnych znakow obcych pism (CJK/cyrylica/greka/hebrajski/arabski/emoji)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
