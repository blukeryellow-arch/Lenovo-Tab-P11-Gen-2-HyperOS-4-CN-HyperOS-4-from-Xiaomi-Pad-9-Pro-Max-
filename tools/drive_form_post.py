#!/usr/bin/env python3
"""Pobieranie pliku z Google Drive przez strone 'Download warning' - bez logowania.

Skad sie wzielo. Runner GitHub Actions probal sciagnac obrazy z Dysku udostepnione
'kazdy z linkiem'. Dla plikow, ktorych Drive nie skanuje antywirusowo (~>100 MB),
GET na drive.usercontent.google.com/download zwraca HTTP 200 z HTML
'<title>Google Drive - Download warning</title>' (ok. 2,5 kB) zamiast bajtow.

Pomiar z 2026-09-23 (raporty drive-probe w repo, bo logow CI nie widac):
  probe .../download?id=<ID>&export=download&authuser=0 : HTTP/2 200, 2567 B, HTML
  probe drive.google.com/uc?export=download&id=<ID>      : HTTP/2 303, 2520 B, HTML
  -> 'formularz zwrocil 0 B'
Zero bajtow wrocilo dlatego, ze pierwsza implementacja POSTowala puste cialo do
action. Na aktualnej stronie Google parametry (id/export/confirm/uuid) siedza w
QUERY samego action, a przycisk 'Download anyway' wykonuje GET - nie POST. Stad
kolejnosc prob ponizej: GET na action z query, POST z polami, GET z polami w query.

Logika jest w pliku, nie w workflow, bo 'run: |' nie znosi zagniezdzonych heredokow,
a to narzedze da sie przetestowac lokalnie bez sieci (see --selftest).

Uzycie:
  ./tools/drive_form_post.py --html strona.html --jar ciasteczka.txt --out obraz.img \
      [--id ID] [--log podsumowanie.txt]
  ./tools/drive_form_post.py --selftest
Wyjscie 0 = plik zapisany (> 4096 B i nie HTML). 2 = brak --html, 3 = strona bez
formularza pobierania (logowanie / inny komunikat), 9 = zadna proba nie dala pliku.
"""
import argparse
import http.cookiejar
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request

UA = ('Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/131.0.0.0 Safari/537.36')


def parse_form(html, fallback_id=''):
    """(url, [(nazwa, wartosc)]) dla formularza pobierania ze strony ostrzezenia.

    Bierze <form>, ktorego action zawiera 'download' - NIE pierwsze lepsze, bo na
    stronie jest tez formularz logowania. Jezeli parametry sa w query action (stan
    Google na 2026), trafiaja do listy pol, dzieki czemu da sie je uzyc w kazdej
    z trzech prob.
    """
    picked = None
    for m in re.finditer(r'<form\b([^>]*)>(.*?)</form>', html, re.S | re.I):
        attrs, inner = m.group(1), m.group(2)
        act = re.search(r'action="([^"]*)"', attrs)
        act = act.group(1) if act else ''
        if 'download' in act.lower():
            picked = (act, inner)
            break
        if picked is None and act:
            picked = (act, inner)
    if picked is None:
        m = re.search(r'action="([^"]*download[^"]*)"', html, re.I)
        if not m:
            return None, []
        picked = (m.group(1), html)
    url, inner = picked
    if url.startswith('/'):
        url = 'https://drive.usercontent.google.com' + url

    fields = []
    for tag in re.finditer(r'<input\b[^>]*>', inner, re.I):
        t = tag.group(0)
        n = re.search(r'name="([^"]+)"', t)
        if not n:
            continue
        v = re.search(r'value="([^"]*)"', t)
        fields.append((n.group(1), v.group(1) if v else ''))
    have = [k for k, _ in fields]
    if fallback_id and 'id' not in have:
        fields.append(('id', fallback_id))
    for k, v in urllib.parse.parse_qsl(url.split('?', 1)[1] if '?' in url else ''):
        if k not in [x for x, _ in fields]:
            fields.append((k, v))
    have = [k for k, _ in fields]
    if 'confirm' not in have:
        fields.append(('confirm', 't'))
    if 'export' not in have:
        fields.append(('export', 'download'))
    return url, fields


def looks_like_file(path):
    try:
        n = os.path.getsize(path)
    except OSError:
        return 0, False
    if n <= 4096:
        return n, False
    with open(path, 'rb') as f:
        head = f.read(16).lstrip().lower()
    return n, not head.startswith((b'<!doc', b'<html'))


def selftest():
    """Test bez sieci: dwa uklada strony Google + strona logowania."""
    starszy = ('<html><head><title>Google Drive - Download warning</title></head><body>'
               '<form action="https://accounts.google.com/ServiceLogin"><input name="Email" value="x"></form>'
               '<form action="https://drive.usercontent.google.com/download" method="post">'
               '<input type="hidden" name="id" value="AAA"><input type="hidden" name="uuid" value="u1">'
               '<input type="hidden" name="confirm" value="t"><input type="hidden" name="export" value="download">'
               '</form></body></html>')
    nowszy = ('<html><body><form id="download-form" '
              'action="https://drive.usercontent.google.com/download?id=BBB&export=download'
              '&confirm=t&uuid=deadbeef" method="post">'
              '<input type="submit" value="Download anyway" class="goog-inline-block"></form></body></html>')
    ok = True
    url, f1 = parse_form(starszy, 'X')
    d1 = dict(f1)
    if not (url.endswith('/download') and d1['id'] == 'AAA' and d1['uuid'] == 'u1'
            and d1['confirm'] == 't' and 'Email' not in d1):
        print("FAIL (starszy uklad):", url, f1); ok = False
    else:
        print("OK  starszy uklad: POST z polami ukrytymi, formularz logowania zignorowany")
    url2, f2 = parse_form(nowszy, 'X')
    d2 = dict(f2)
    if not ('id=BBB' in url2 and d2.get('uuid') == 'deadbeef' and d2.get('confirm') == 't'):
        print("FAIL (nowszy uklad):", url2, f2); ok = False
    else:
        print("OK  nowszy uklad: parametry wziete z query action (GET, nie pusty POST)")
    u3, f3 = parse_form('<html><body>Sign in</body></html>', 'Y')
    if u3 is not None or f3:
        print("FAIL (strona logowania nie zostala odrzucona):", u3, f3); ok = False
    else:
        print("OK  strona bez formularza pobierania -> rc 3 (nie udajemy sukcesu)")
    h2 = starszy.replace('<input type="hidden" name="confirm" value="t">', '') \
                .replace('<input type="hidden" name="export" value="download">', '') \
                .replace('<input type="hidden" name="id" value="AAA">', '')
    d4 = dict(parse_form(h2, 'GOTOWE')[1])
    if not (d4.get('id') == 'GOTOWE' and d4.get('confirm') == 't' and d4.get('export') == 'download'):
        print("FAIL (uzupelnianie pol):", d4); ok = False
    else:
        print("OK  brakujace pola uzupelnione (id z --id, confirm=t, export=download)")
    print("SELFTEST:", "WSZYSTKIE TESTY OK" if ok else "SA PORAZKI")
    return 0 if ok else 1


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--html', required=True)
    ap.add_argument('--jar')
    ap.add_argument('--out', required=True)
    ap.add_argument('--id', default='')
    ap.add_argument('--log')
    ap.add_argument('--selftest', action='store_true')
    ap.add_argument('--max-bytes', type=int, default=12 * 1024 * 1024 * 1024)
    a = ap.parse_args()
    if a.selftest:
        return selftest()

    try:
        html = open(a.html, encoding='utf-8', errors='replace').read()
    except OSError as e:
        print("nie ma pliku strony: %s" % e, file=sys.stderr)
        return 2
    url, fields = parse_form(html, a.id)
    if not url:
        print("na stronie nie ma formularza pobierania - to logowanie albo inny komunikat",
              file=sys.stderr)
        return 3

    cj = http.cookiejar.MozillaCookieJar()
    if a.jar and os.path.exists(a.jar):
        try:
            cj.load(ignore_discard=True, ignore_expires=True)
            print("ciasteczka: %d z %s" % (len(list(cj)), a.jar), file=sys.stderr)
        except Exception as e:
            print("ciasteczek nie wczytano (%s) - probujemy bez" % e, file=sys.stderr)
    opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj))

    body = urllib.parse.urlencode(fields).encode()
    sep = '&' if '?' in url else '?'
    attempts = []
    if '?' in url:
        attempts.append(('GET', url, None))                      # przycisk 'Download anyway'
    attempts.append(('POST', url, body))                          # starszy uklad z inputami
    attempts.append(('GET', url + sep + urllib.parse.urlencode(fields), None))

    log = ["formularz: %s" % url, "pola: %r" % (fields,)]
    for method, target, data in attempts:
        n0 = 0
        print("%s %s" % (method, target[:150]), file=sys.stderr)
        try:
            req = urllib.request.Request(target, data=data, method=method)
            req.add_header('User-Agent', UA)
            req.add_header('Referer', 'https://drive.google.com/')
            if data is not None:
                req.add_header('Content-Type', 'application/x-www-form-urlencoded')
                req.add_header('Origin', 'https://drive.google.com')
            with opener.open(req, timeout=1800) as r:
                status = getattr(r, 'status', r.getcode())
                with open(a.out, 'wb') as f:
                    while True:
                        chunk = r.read(1 << 20)
                        if not chunk:
                            break
                        f.write(chunk)
                        n0 += len(chunk)
                        if n0 > a.max_bytes:
                            print("przekroczony limit rozmiaru - przerywam", file=sys.stderr)
                            log.append("%s -> przekroczony limit %d B" % (method, a.max_bytes))
                            if a.log:
                                open(a.log, 'w', encoding='utf-8').write("\n".join(log) + "\n")
                            return 4
        except urllib.error.HTTPError as e:
            note = ""
            try:
                note = " | " + e.read(200).decode('utf-8', 'replace')
            except Exception:
                pass
            print("HTTP %s %s na %s%s" % (e.code, e.reason, method, note[:180]), file=sys.stderr)
            log.append("%s -> HTTP %s%s" % (method, e.code, note[:180]))
            continue
        except Exception as e:
            print("blad transportu na %s: %s: %s" % (method, type(e).__name__, e), file=sys.stderr)
            log.append("%s -> blad %s: %s" % (method, type(e).__name__, e))
            continue

        n, good = looks_like_file(a.out)
        log.append("%s -> %d B, plik=%s" % (method, n, 'tak' if good else 'NIE'))
        if good:
            print("HTTP %s, zapisano %d B - to jest plik" % (status, n), file=sys.stderr)
            if a.log:
                open(a.log, 'w', encoding='utf-8').write("\n".join(log) + "\n")
            return 0
        print("  odzywka nie jest plikiem (%d B) - nastepna proba" % n, file=sys.stderr)

    if a.log:
        open(a.log, 'w', encoding='utf-8').write("\n".join(log) + "\n")
    print("zadna z prob (%s) nie dawla pliku" % ", ".join(m for m, _, _ in attempts), file=sys.stderr)
    return 9


if __name__ == '__main__':
    sys.exit(main())
