#!/usr/bin/env python3
"""Sprawdzenie skladni kazdego kroku `run:` w workflow GitHub Actions.

Powstal po realnej awarii: job `drive-probe` umarl kodem 127, bo tekst komunikatu
zostal rozbity na dwie linie bez kontynuacji backslashem - drugi wiersz
('usercontent (...)') byl dla basha wywolaniem polecenia. YAML byl poprawny,
actionlint nic nie zglosil, a logow CI agent nie widzi (objects.githubusercontent.com
= 000), zostaje tylko adnotacja check-run "[failure] Process completed with exit
code 127". Stad lokalny test: wyciagamy ciala krokow i puszczamy przez `bash -n`,
plus heurystyka dla linii o ksztalcie nie-bedacym poleceniem.

Dziala bez zaleznosci (heurystyka po wcieciach); z PyYAML dokladnie (nazwy krokow i
pelna struktura).

Uzycie:
  ./tools/lint_workflow_steps.py                     # wszystkie workflow w repo
  ./tools/lint_workflow_steps.py .github/workflows/x.yml
"""
import os
import re
import subprocess
import sys
import tempfile

try:
    import yaml
    HAVE_YAML = True
except ImportError:  # bez zaleznosci - tryb heurystyczny
    yaml = None
    HAVE_YAML = False

QUOTE_START = re.compile(r'^["\'(]')
OK_PREFIXES = ('#', '>', '<', '|', '&', '$(', '"$(', "'$('")


def pairs_from_yaml(path):
    doc = yaml.safe_load(open(path, encoding='utf-8'))
    out = []
    for job, jv in (doc.get('jobs') or {}).items():
        for st in (jv.get('steps') or []):
            body = st.get('run')
            if body:
                out.append((f"{job}/{st.get('name') or st.get('uses') or '?'}", body))
    return out


def pairs_from_indentation(path):
    """Fallback bez PyYAML: `run: |` + wcieci. Nazwa = ostatnie `- name:` przed blokiem."""
    lines = open(path, encoding='utf-8').read().splitlines()
    out, cur, i, n = [], '?', 0, len(lines)
    while i < n:
        ln = lines[i]
        s = ln.strip()
        if s.startswith('- name:'):
            cur = s.split(':', 1)[1].strip() or '?'
            i += 1
            continue
        if s.startswith('run:'):
            block = s[4:].strip()
            if not block.startswith('|') and not block.startswith('>'):
                i += 1
                continue  # run: 'jedna linia'
            ind = len(ln) - len(ln.lstrip())
            body, i = [], i + 1
            while i < n:
                nl = lines[i]
                nind = len(nl) - len(nl.lstrip())
                if nl.strip() == '':
                    body.append('')
                    i += 1
                    continue
                if nind <= ind:
                    break
                body.append(nl[ind + 2:] if len(nl) > ind + 2 else '')
                i += 1
            out.append((cur, '\n'.join(body)))
            continue
        i += 1
    return out


def check(path):
    """(liczba krokow, lista problemow)."""
    if HAVE_YAML:
        try:
            pairs = pairs_from_yaml(path)
        except yaml.YAMLError as e:
            return 0, [f"YAML BLAD: {str(e).splitlines()[0][:160]}"]
        note = ''
    else:
        pairs = pairs_from_indentation(path)
        note = ' (tryb heurystyczny, bez PyYAML)'

    problems = []
    for name, body in pairs:
        with tempfile.NamedTemporaryFile('w', suffix='.sh', delete=False, encoding='utf-8') as f:
            f.write(body)
            tmp = f.name
        try:
            r = subprocess.run(['bash', '-n', tmp], capture_output=True, text=True, timeout=60)
            if r.returncode:
                problems.append(f"{name}: bash -n -> {r.stderr.strip()[:220]}")
        except Exception as e:  # lint nie ma nigdy wywalcic calej kontroli
            problems.append(f"{name}: nie udalo sie odpalic bash -n: {e}")
        finally:
            os.unlink(tmp)

        prev_continuation = False
        for i, line in enumerate(body.splitlines(), 1):
            ls = line.strip()
            if prev_continuation:
                prev_continuation = ls.endswith('\\')
                continue
            prev_continuation = ls.endswith('\\')
            if not ls or ls.startswith(('#', ':', 'echo', 'printf', 'if', 'for', 'done', '}')):
                continue
            if QUOTE_START.match(ls) and not ls.startswith(OK_PREFIXES):
                problems.append(f"{name}:{i}: linia zaczyna sie od cudzyslowa/nawiasu - "
                                f"wyglada na tekst wziety za polecenie: {ls[:66]}")
            if '`' in line and '${' in line and 'GITHUB_ENV' not in line:
                problems.append(f"{name}:{i}: backtick obok interpolacji ${{}} - sprawdz cytaty")
            if re.search(r'\$\{\{\s*inputs\.[a-z_]+\s*\}\}', line) and 'if:' not in line and '-f ' not in line:
                pass  # dozwolone, tylko odnotowujemy ze nie ma bramki (patrz krok wczytujacy)
    return len(pairs), problems, note


def main(argv):
    paths = argv or []
    if not paths:
        wd = os.path.join('.github', 'workflows')
        if not os.path.isdir(wd):
            print("brak .github/workflows - podaj plik jawnie", file=sys.stderr)
            return 2
        paths = sorted(os.path.join(wd, f) for f in os.listdir(wd) if f.endswith(('.yml', '.yaml')))
    total = 0
    for p in paths:
        if not os.path.exists(p):
            print(f"{p}: NIE ISTNIEJE")
            total += 1
            continue
        res = check(p)
        n, probs, note = res if len(res) == 3 else (res[0], res[1], '')
        print(f"{p}: {n} krokow `run:` sprawdzonych{note}")
        for x in probs:
            print(f"  {x}")
        total += len(probs)
    print("LINT KROKOW:", "OK - brak rzeczy do sprawdzenia" if not total else f"{total} uwag")
    return 0 if not total else 1


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
