#!/usr/bin/env python3
"""Omijanie strony 'Google Drive - Download warning' bez logowania.

Dlaczego to istnieje. Runner GitHub Actions pobieral obrazy z Dysku linkiem
'kazdy z linkiem'. Dla plikow, ktorych Drive nie skanuje antywirusowo (progi rzedu
~100 MB), GET na drive.usercontent.google.com/download zwraca HTTP 200 z HTML
'<title>Google Drive - Download warning</title>' (ok. 2,5 kB), a nie plik.
Przycisk 'Download anyway' w przegladarce POSTuje formularz z tej strony - mozna go
odtworzyc bez JS, trzeba tylko wziac action i WSZYSTKIE pola ukryte z wlasciwego
<form>. Pierwsza proba w CI zwrocila 0 bajtow wlasnie dlatego, ze sed bral pierwszy
'action=' na stronie (formularz logowania) i gubil `uuid`/`confirm`.

Skrypt zglasza dokladnie co wyslal i co dostal (stderr + --log), bo logow CI nie
widac - raport w repo jest jedynym kanalem diagnostyki.

Uzycie:
  ./tools/drive_form_post.py --html strona.html --jar ciasteczka.txt --out obraz.img \
      [--id ID] [--log podsumowanie.txt]
Wyjscie 0 i plik > 4096 B = pobrano. Kod 3 = na stronie nie ma formularza pobierania
(logowanie/kolejny komunikat), 5-8 = POST odebral inaczej niz plik.
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
DL = 'download'


def parse_form(html, fallback_id=''):
    """(url, [(nazwa, wartosc)]) dla formularza pobierania ze strony ostrzezenia."""
    picked = None
    for m in re.finditer(r'<form\b([^>]*)>(.*?)</form>', html, re.S | re.I):
        attrs, inner = m.group(1), m.group(2)
        act = re.search(r'action="([^"]*)"', attrs)
        act = act.group(1) if act else ''
        if DL in act.lower():
            picked = (act, inner)
            break
        if picked is None and act:
            picked = (act, inner)
    if picked is None:
        m = re.search(r'action="([^"]*' + DL + r'[^"]*)"', html, re.I)
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
    if 'confirm' not in have:
        fields.append(('confirm', 't'))
    if 'export' not in have:
        fields.append(('export', 'download'))
    return url, fields


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--html', required=True)
    ap.add_argument('--jar')
    ap.add_argument('--out', required=True)
    ap.add_argument('--id', default='')
    ap.add_argument('--log')
    ap.add_argument('--max-bytes', type=int, default=12 * 1024 * 1024 * 1024)
    a = ap.parse_args()

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
    body = urllib.parse.urlencode(fields)
    print("POST %s" % url, file=sys.stderr)
    print("pola: " + ", ".join("%s=%s" % (k, '<ustawione>' if v else '<puste>')
                               for k, v in fields), file=sys.stderr)

    cj = http.cookiejar.MozillaCookieJar()
    if a.jar and os.path.exists(a.jar):
        try:
            cj.load(ignore_discard=True, ignore_expires=True)
            print("ciasteczka: %d z %s" % (len(list(cj)), a.jar), file=sys.stderr)
        except Exception as e:
            print("ciasteczek nie udalo sie wczytac (%s) - probujemy bez" % e, file=sys.stderr)

    req = urllib.request.Request(url, data=body.encode(), method='POST')
    req.add_header('User-Agent', UA)
    req.add_header('Content-Type', 'application/x-www-form-urlencoded')
    req.add_header('Origin', 'https://drive.google.com')
    req.add_header('Referer', 'https://drive.google.com/')
    opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj))
    status, hdrs, n = None, {}, 0
    try:
        with opener.open(req, timeout=1800) as r:
            status, hdrs = getattr(r, 'status', r.getcode()), dict(r.headers)
            with open(a.out, 'wb') as f:
                while True:
                    chunk = r.read(1 << 20)
                    if not chunk:
                        break
                    f.write(chunk)
                    n += len(chunk)
                    if n > a.max_bytes:
                        print("przekroczony limit rozmiaru - przerywam", file=sys.stderr)
                        return 4
    except urllib.error.HTTPError as e:
        print("HTTP %s %s na POST" % (e.code, e.reason), file=sys.stderr)
        try:
            print("cialo (pierwsze 200 B): " + e.read(200).decode('utf-8', 'replace'), file=sys.stderr)
        except Exception:
            pass
        if a.log:
            open(a.log, 'w', encoding='utf-8').write("POST %s -> HTTP %s\n" % (url, e.code))
        return 5
    except Exception as e:
        print("blad transportu: %s: %s" % (type(e).__name__, e), file=sys.stderr)
        if a.log:
            open(a.log, 'w', encoding='utf-8').write("POST %s -> blad %s: %s\n" % (url, type(e).__name__, e))
        return 6

    print("HTTP %s, zapisano %d B" % (status, n), file=sys.stderr)
    if a.log:
        with open(a.log, 'w', encoding='utf-8') as f:
            f.write("POST %s status=%s bytes=%d\n" % (url, status, n))
            for k in ('content-type', 'content-disposition', 'content-length', 'server'):
                if k in hdrs:
                    f.write("  %s: %s\n" % (k, hdrs[k]))
            f.write("pola: %r\n" % (fields,))
    if n <= 4096:
        head = open(a.out, 'rb').read(300).decode('utf-8', 'replace')
        print("za malo bajtow (%d); pierwsze 300 B: %s" % (n, head[:280]), file=sys.stderr)
        return 7
    if open(a.out, 'rb').read(16).lstrip().lower().startswith((b'<!doc', b'<html')):
        print("dostalismy HTML zamiast obrazu", file=sys.stderr)
        return 8
    print("OK", file=sys.stderr)
    return 0


if __name__ == '__main__':
    sys.exit(main())
