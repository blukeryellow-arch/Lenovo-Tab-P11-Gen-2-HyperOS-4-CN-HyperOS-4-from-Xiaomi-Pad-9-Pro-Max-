#!/usr/bin/env python3
"""httpzip.py - czytanie wpisow ZIP przez HTTP range requests (bez pobierania
calosci na dysk).

Cel: bazowy zip lolinet (4,47G) zawiera super.img RAW 8,3G (deflate). Dysk
runera 8-14G wolnych nie miesci zipa + super. Ten skrypt udostepnia wpis zipa
jako strumen na stdout, czytajac TYLKO potrzebne zakresy HTTP (lolinet: 206,
receipt base-probe 36605363414).

Uzycie:
  httpzip.py URL --list                      -> lista wpisow
  httpzip.py URL --entry 'sciezka/w/zipie'   -> surowa zawartosc na stdout
  httpzip.py URL --probe                     -> HEAD + accept-ranges (kontrola)

Implementacja: HTTPRangeFile - obiekt plikopodobny (read/seek/tell) z okienkowym
buforem (prefetch 16M), przekazywany do zipfile.ZipFile.
"""
import io
import sys
import urllib.request

BLOCK = 32 * 1024 * 1024  # prefetch 32M -> ~145 requestow na 4,5G


class HTTPRangeFile(io.RawIOBase):
    def __init__(self, url, block=BLOCK):
        self.url = url
        self.block = block
        req = urllib.request.Request(url, method="HEAD")
        with urllib.request.urlopen(req, timeout=60) as r:
            self.size = int(r.headers.get("Content-Length", "0"))
            self.accepts = r.headers.get("Accept-Ranges", "none")
        if self.size <= 0:
            raise SystemExit(f"brak Content-Length dla {url}")
        if "bytes" not in self.accepts:
            raise SystemExit(f"serwer nie wspiera range requests (Accept-Ranges: {self.accepts})")
        self.pos = 0
        self._buf = b""
        self._buf_start = -1
        self.requests = 0

    def seek(self, off, whence=0):
        if whence == 0:
            self.pos = off
        elif whence == 1:
            self.pos += off
        elif whence == 2:
            self.pos = self.size + off
        return self.pos

    def tell(self):
        return self.pos

    def seekable(self):
        return True

    def readable(self):
        return True

    def _fetch(self, start, length):
        end = min(start + length, self.size) - 1
        if start > end:
            return b""
        last_err = None
        for attempt in range(4):
            try:
                req = urllib.request.Request(
                    self.url, headers={"Range": f"bytes={start}-{end}"})
                self.requests += 1
                with urllib.request.urlopen(req, timeout=180) as r:
                    data = r.read()
                if len(data) == end - start + 1:
                    return data
                last_err = f"krotki range: chciano {end-start+1}, dostano {len(data)}"
            except Exception as e:
                last_err = f"{type(e).__name__}: {e}"
            sys.stderr.write(f"# httpzip: retry {attempt+1}/4 @ {start}: {last_err}\n")
            import time; time.sleep(3 * (attempt + 1))
        raise SystemExit(f"httpzip: range {start}-{end} padl po 4 probach: {last_err}")

    def read(self, n=-1):
        if n is None or n < 0:
            n = self.size - self.pos
        if n == 0:
            return b""
        # czy w buforze?
        if not (self._buf_start <= self.pos < self._buf_start + len(self._buf)):
            fetch = max(n, self.block)
            self._buf = self._fetch(self.pos, fetch)
            self._buf_start = self.pos
        off = self.pos - self._buf_start
        out = self._buf[off:off + n]
        self.pos += len(out)
        return out


def main():
    argv = sys.argv[1:]
    url = argv[0]
    if "--probe" in argv:
        f = HTTPRangeFile(url)
        print(f"size={f.size} accept-ranges={f.accepts}")
        probe = f._fetch(0, 64)
        print(f"pierwsze 64B: {probe[:64].hex()}")
        return
    f = HTTPRangeFile(url)
    import zipfile
    z = zipfile.ZipFile(f)
    if "--list" in argv:
        for i in z.infolist():
            print(f"{i.file_size}\t{i.compress_size}\t{i.filename}")
        return
    if "--entry" in argv:
        name = argv[argv.index("--entry") + 1]
        names = [i.filename for i in z.infolist()]
        if name not in names:
            cands = [n for n in names if n.endswith("/" + name) or n.endswith(name)]
            if len(cands) != 1:
                raise SystemExit(f"brak jednoznacznego wpisu '{name}': {cands[:5]}")
            name = cands[0]
        try:
            with z.open(name) as e:
                while True:
                    buf = e.read(4 * 1024 * 1024)
                    if not buf:
                        break
                    sys.stdout.buffer.write(buf)
                sys.stdout.buffer.flush()
        except BrokenPipeError:
            # konsument zakonczyl wczesniej (np. stream_lpunpack po ostatnim
            # segmencie) - dane kompletne, to nie blad
            sys.stderr.write(f"# httpzip: {name} konsument zamknal pipe (OK)\n")
            return
        sys.stderr.write(f"# httpzip: {name} OK ({f.requests} requestow HTTP)\n")
        return
    raise SystemExit(__doc__)


if __name__ == "__main__":
    main()
