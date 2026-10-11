#!/usr/bin/env python3
"""Naklada konteksty SELinux (security.selinux) na drzewo wg plat_file_contexts.

Po co: ekstrakcja ext4 przez debugfs rdump NIE restoruje xattr (konteksty
gina), a GSI Androida jest ENFORCING - pliki bez kontekstu dostaja unlabeled
i system pada na denialach. To narzedzie parsuje plat_file_contexts SAMEGO
obrazu (system/etc/selinux/plat_file_contexts) i ustawia security.selinux
na kazdym pliku drzewa (potrzebne root: sudo - security.* jest privileged).

Semantyka dopasowania (wg libselinux selabel_file, wystarczajaco blisko):
  - regex dopasowany od poczatku sciezki (wpisy zaczynaja sie od /),
  - sposrod pasujacych wygrywa NAJDLUZSZY "stem" (literal przed pierwszym
    znakiem metaznakowym regexu); remis -> pozniejszy wiersz pliku,
  - wiersze z typem pliku (-d/-f/-l/-c/-b/-p/-s) dotycza tylko tego typu.

Uzycie:
  sudo tools/fc_fixup.py --contexts PLAT_FC --root DRZEWO [--dry-run] \
      [--only SCIEZKA ...] [--report PLIK]

Kod 0 = OK (raport: dopasowane/niedopasowane); 2 = brak pliku kontekstow.
"""
import argparse
import os
import re
import sys

TYPE_CHARS = {
    "-d": "dir", "-f": "file", "-l": "symlink", "-c": "char",
    "-b": "block", "-p": "fifo", "-s": "socket",
}

META = re.compile(r"[^A-Za-z0-9/\_.\-]")


def parse_contexts(path):
    entries = []
    for ln in open(path, encoding="utf-8", errors="replace"):
        s = ln.strip()
        if not s or s.startswith("#"):
            continue
        parts = s.split()
        if len(parts) == 2:
            pat, ctx = parts
            ftype = None
        elif len(parts) == 3 and parts[1] in TYPE_CHARS:
            pat, ctx = parts[0], parts[2]
            ftype = TYPE_CHARS[parts[1]]
        else:
            continue
        pat = pat.lstrip("^")
        stem = META.split(pat)[0] if pat else ""
        try:
            rx = re.compile(pat)
        except re.error:
            continue  # wzorce spoza python-regex (rzadkie) - pomijamy z ostroznie
        entries.append((stem, rx, ctx, ftype, s))
    return entries


def path_kind(p, islink):
    if islink:
        return "symlink"
    if os.path.isdir(p):
        return "dir"
    if os.path.isfile(p):
        return "file"
    if os.path.ischarfile(p) if hasattr(os.path, "ischarfile") else False:
        return "char"
    return "other"


def match(path, entries):
    best = None
    for idx, (stem, rx, ctx, ftype, raw) in enumerate(entries):
        if rx.match(path) is None:
            continue
        if best is None or len(stem) >= best[0]:
            best = (len(stem), idx, ctx, ftype, raw)
    return best


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--contexts", required=True)
    ap.add_argument("--root", required=True)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--only", nargs="*", default=[],
                    help="ogranicz do tych sciezek wzgledem --root")
    ap.add_argument("--report")
    args = ap.parse_args()

    if not os.path.isfile(args.contexts):
        print("brak pliku kontekstow: %s" % args.contexts, file=sys.stderr)
        return 2
    entries = parse_contexts(args.contexts)
    print("wpisow kontekstowych: %d" % len(entries))

    targets = []
    if args.only:
        for rel in args.only:
            p = os.path.join(args.root, rel)
            if os.path.isdir(p) and not os.path.islink(p):
                for dp, dns, fns in os.walk(p):
                    targets.append(dp)
                    for fn in fns:
                        targets.append(os.path.join(dp, fn))
            else:
                targets.append(p)
        targets.append(args.root)
    else:
        targets.append(args.root)
        for dp, dns, fns in os.walk(args.root):
            targets.extend([os.path.join(dp, d) for d in dns])
            targets.extend([os.path.join(dp, f) for f in fns])

    ok = miss = set_x = 0
    misses = []
    per_ctx = {}
    for p in targets:
        rel = "/" + os.path.relpath(p, args.root).replace(os.sep, "/")
        if rel == "/.":
            rel = "/"
        islink = os.path.islink(p)
        m = match(rel, entries)
        if m is None:
            miss += 1
            misses.append(rel)
            continue
        _, _, ctx, ftype, raw = m
        kind = "symlink" if islink else ("dir" if os.path.isdir(p) else "file")
        if ftype and ftype != kind:
            miss += 1
            misses.append(rel + " (typ %s != %s)" % (kind, ftype))
            continue
        per_ctx[ctx] = per_ctx.get(ctx, 0) + 1
        if not args.dry_run:
            try:
                os.setxattr(p, "security.selinux", ctx.encode(),
                            follow_symlinks=False)
                set_x += 1
            except PermissionError:
                print("EPERM na %s - uruchom z sudo (security.* wymaga roota)" % rel,
                      file=sys.stderr)
                return 3
        ok += 1
    print("dopasowane: %d (xattr ustawione: %d)  niedopasowane: %d"
          % (ok, set_x, miss))
    for ctx in sorted(per_ctx, key=per_ctx.get, reverse=True)[:12]:
        print("  %6d  %s" % (per_ctx[ctx], ctx))
    if misses:
        for r in misses[:15]:
            print("  BRAK: %s" % r)
    if args.report:
        with open(args.report, "w", encoding="utf-8") as f:
            f.write("# fc_fixup report (dry_run=%s)\n" % args.dry_run)
            f.write("# dopasowane=%d niedopasowane=%d\n" % (ok, miss))
            for r in misses:
                f.write("MISS %s\n" % r)
    return 0


if __name__ == "__main__":
    sys.exit(main())
