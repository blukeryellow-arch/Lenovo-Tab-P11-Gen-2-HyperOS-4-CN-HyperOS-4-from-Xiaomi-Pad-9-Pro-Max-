#!/usr/bin/env python3
"""Serwer dostawy plikow przez preview sandboxa: listing + pobieranie z Range (resume).

Bez zaleznosci. Uzycie:
  ./serve_dl.py [katalog] [port]
Klik w plik = pobieranie (Content-Disposition: attachment).
"""
import http.server
import os
import re
import socketserver
import sys
import urllib.parse

ROOT = os.path.realpath(sys.argv[1] if len(sys.argv) > 1 else '.')
PORT = int(sys.argv[2]) if len(sys.argv) > 2 else 8000
TITLE = 'HyperOS 4 - Lenovo Tab P11 Gen 2'


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'
    server_version = 'dl/1.0'

    def _listing(self):
        items = []
        for f in sorted(os.listdir(ROOT)):
            p = os.path.join(ROOT, f)
            if os.path.isfile(p):
                items.append('<li><a href="/%s">%s</a> &mdash; %s B</li>'
                             % (urllib.parse.quote(f), f, format(os.path.getsize(p), ',')))
        return ('<!doctype html><meta charset="utf-8"><title>%s</title>'
                '<h2>%s</h2><p>system (sparse) + vbmeta &mdash; kliknij plik, aby pobrac:</p><ul>%s</ul>'
                % (TITLE, TITLE, ''.join(items))).encode('utf-8')

    def _resolve(self):
        path = urllib.parse.unquote(self.path.split('?', 1)[0])
        if path in ('', '/'):
            return None, None
        fp = os.path.realpath(os.path.join(ROOT, path.lstrip('/')))
        if not (fp == ROOT or fp.startswith(ROOT + os.sep)) or not os.path.isfile(fp):
            return None, None
        return fp, path

    def _send(self, head_only=False):
        if self.path.split('?', 1)[0] in ('', '/'):
            body = self._listing()
            self.send_response(200)
            self.send_header('Content-Type', 'text/html; charset=utf-8')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            if not head_only:
                self.wfile.write(body)
            return
        fp, _ = self._resolve()
        if fp is None:
            self.send_error(404, 'nie ma takiego pliku')
            return
        size = os.path.getsize(fp)
        start, end, status = 0, size - 1, 200
        rng = self.headers.get('Range')
        if rng:
            m = re.match(r'^bytes=(\d*)-(\d*)$', rng.strip())
            if m and (m.group(1) or m.group(2)):
                if m.group(1):
                    start = int(m.group(1))
                    if m.group(2):
                        end = min(int(m.group(2)), size - 1)
                else:  # zakres koncowy: bytes=-N
                    start, end = max(0, size - int(m.group(2))), size - 1
                if start > end or start >= size:
                    self.send_error(416, 'zly zakres')
                    return
                status = 206
        self.send_response(status)
        self.send_header('Content-Type', 'application/octet-stream')
        self.send_header('Content-Disposition', 'attachment; filename="%s"' % os.path.basename(fp))
        self.send_header('Accept-Ranges', 'bytes')
        if status == 206:
            self.send_header('Content-Range', 'bytes %d-%d/%d' % (start, end, size))
        self.send_header('Content-Length', str(end - start + 1))
        self.end_headers()
        if head_only:
            return
        with open(fp, 'rb') as fh:
            fh.seek(start)
            remaining = end - start + 1
            while remaining > 0:
                chunk = fh.read(min(1024 * 1024, remaining))
                if not chunk:
                    break
                try:
                    self.wfile.write(chunk)
                except (BrokenPipeError, ConnectionResetError):
                    return
                remaining -= len(chunk)

    def do_GET(self):
        self._send(head_only=False)

    def do_HEAD(self):
        self._send(head_only=True)


class Server(socketserver.ThreadingTCPServer):
    daemon_threads = True
    allow_reuse_address = True


if __name__ == '__main__':
    print('serwuje %s na 0.0.0.0:%d' % (ROOT, PORT), flush=True)
    Server(('0.0.0.0', PORT), Handler).serve_forever()
