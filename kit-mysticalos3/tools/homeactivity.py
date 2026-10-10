#!/usr/bin/env python3
"""homeactivity.py <aapt2-dump-xmltree.txt> <pkg> — wypisuje pelna nazwe aktywnosci HOME.

Launchery NIE deklarujcategory LAUNCHER (aapt2 badging milczy) — uzywaja
android.intent.category.HOME + DEFAULT. Ten parser czyta wyjscie
`aapt2 dump xmltree --file AndroidManifest.xml` i zwraca pierwsza aktywnosc
(lub activity-alias) z filtrem HOME. Nazwy wzgledne sa expandowane o pakiet.
"""
import re
import sys

act_re = re.compile(r'E:\s*activity(-alias)?\b')
name_re = re.compile(r'android:name[^=]*="([^"]+)"')
cat_re = re.compile(r'android\.intent\.category\.HOME\b')


def main():
    txt = open(sys.argv[1], encoding='utf-8', errors='ignore').read()
    pkg = sys.argv[2]
    cur, in_act, found = None, False, []
    for ln in txt.splitlines():
        if act_re.search(ln) and 'intent-filter' not in ln:
            in_act = True
            m = name_re.search(ln)
            cur = m.group(1) if m else None
            continue
        if not in_act:
            continue
        if 'intent-filter' in ln:
            continue
        if cat_re.search(ln) and cur:
            found.append(cur)
            in_act, cur = False, None
            continue
        m = name_re.search(ln)
        if m and cur is None:
            cur = m.group(1)

    def expand(a):
        if a.startswith('.'):
            return pkg + a
        if '.' not in a:
            return pkg + '.' + a
        return a

    if found:
        print(expand(found[0]))
    return 0


if __name__ == '__main__':
    sys.exit(main())
