#!/usr/bin/env python3
"""propctx.py - forensyka + fix property_contexts vs typy polityki SELinux.

TEORIA: bionic __system_property_area_init tworzy plik /dev/__properties__
DLA KAZDEGO kontekstu z property_contexts i robi fsetxattr(security.selinux,
"u:object_r:TYP:s0"). Jesli TYP nie istnieje w ZALADOWANEJ polityce, kernel
odrzuca etykiete (EINVAL) -> area_init zwraca -1 -> init: FATAL "Failed to
initialize property area" -> InitFatalReboot -> BOOTLOOP.

Tryby:
  check <ctx_dir> [--extra-cil <plik.cil>]...
        - zbiera pliki *_property_contexts z ctx_dir (+ sepolicy CILE z
          ctx_dir i --extra-cil), wypisuje typy uzyte w kontekstach,
          ktore NIE SA zadeklarowane w zadnym CIL-u (podejrzane).
  fix   <ctx_dir> [--extra-cil <plik.cil>]... [--fallback default_prop]
        - przepisuje w miejscu pliki *_property_contexts z ctx_dir:
          nieznane typy -> fallback. (Tylko pliki w ctx_dir; vendor
          zostaje nietkniety jesli nie podamy jego katalogu.)
Tylko stdlib - do uruchamiania jako sudo python3 na zamontowanych obrazach.
"""
import os
import re
import sys

CTX_GLOB = ("plat_property_contexts", "system_ext_property_contexts",
            "product_property_contexts", "odm_property_contexts",
            "vendor_property_contexts")
TYPE_DECL = re.compile(r"\(\s*type\s+([A-Za-z0-9_]+)\s*\)")
CTX_FIELD = re.compile(r"u:object_r:([A-Za-z0-9_]+):s0")


def find_files(ctx_dir):
    ctxs = [f for f in CTX_GLOB if os.path.isfile(os.path.join(ctx_dir, f))]
    cils = [f for f in os.listdir(ctx_dir) if f.endswith(".cil")]
    return ctxs, cils


def declared_types(ctx_dir, extra_cils):
    types = set()
    paths = [os.path.join(ctx_dir, f) for f in os.listdir(ctx_dir)
             if f.endswith(".cil")] + list(extra_cils)
    for p in paths:
        try:
            with open(p, "r", errors="replace") as r:
                types.update(TYPE_DECL.findall(r.read()))
        except OSError as e:
            print("UWAGA: nie moge czytac %s: %s" % (p, e))
    return types, paths


def parse_contexts(path):
    """zwraca liste (lineno, prop, typ, oryginalna_linia)"""
    out = []
    with open(path, "r", errors="replace") as r:
        for i, line in enumerate(r, 1):
            s = line.strip()
            if not s or s.startswith("#"):
                continue
            fields = s.split()
            if len(fields) < 2:
                continue
            m = CTX_FIELD.search(fields[1])
            if m:
                out.append((i, fields[0], m.group(1), line.rstrip("\n")))
    return out


def main():
    if len(sys.argv) < 3 or sys.argv[1] not in ("check", "fix"):
        print(__doc__)
        return 2
    mode, ctx_dir = sys.argv[1], sys.argv[2]
    extra_cils = []
    fallback = "default_prop"
    args = sys.argv[3:]
    i = 0
    while i < len(args):
        if args[i] == "--extra-cil" and i + 1 < len(args):
            extra_cils.append(args[i + 1]); i += 2
        elif args[i] == "--fallback" and i + 1 < len(args):
            fallback = args[i + 1]; i += 2
        else:
            print("nieznany argument: %s" % args[i]); return 2
    if not os.path.isdir(ctx_dir):
        print("brak katalogu: %s" % ctx_dir); return 2

    ctxs, _ = find_files(ctx_dir)
    types, cil_paths = declared_types(ctx_dir, extra_cils)
    print("== propctx %s ==" % mode)
    print("katalog kontekstow : %s" % ctx_dir)
    print("pliki kontekstow   : %s" % (", ".join(ctxs) or "(brak)"))
    print("CILE (deklaracje)  : %s" % ", ".join(cil_paths or ["(brak)"]))
    print("zadeklarowane typy : %d" % len(types))

    missing_total = 0
    for f in ctxs:
        path = os.path.join(ctx_dir, f)
        entries = parse_contexts(path)
        missing = [(ln, prop, t) for (ln, prop, t, _) in entries
                   if t not in types]
        bad_default = [(ln, prop, t) for (ln, prop, t, _) in entries
                       if t == fallback and fallback not in types]
        print("-- %s: %d wpisow, NIEZNANE TYPY: %d%s"
              % (f, len(entries), len(missing),
                 "  (!) fallback tez nieznany" if bad_default else ""))
        for ln, prop, t in missing[:40]:
            print("   linia %d: %s -> %s" % (ln, prop, t))
        if len(missing) > 40:
            print("   ... i %d dalszych" % (len(missing) - 40))
        missing_total += len(missing)
        if mode == "fix" and missing:
            with open(path, "r", errors="replace") as r:
                lines = r.readlines()
            for ln, prop, t in missing:
                s = lines[ln - 1]
                lines[ln - 1] = CTX_FIELD.sub(
                    "u:object_r:%s:s0" % fallback, s, count=1)
            with open(path, "w") as w:
                w.writelines(lines)
            print("   FIX: przepisano %d wpisow na u:object_r:%s:s0"
                  % (len(missing), fallback))
    print("PODSUMOWANIE: nieznanych typow we wpisach: %d" % missing_total)
    if missing_total and mode == "check":
        print("HIPOTEZA: te typy nie istnieja w polityce -> fsetxattr EINVAL "
              "-> __system_property_area_init = -1 -> FATAL property.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
