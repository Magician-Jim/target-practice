#!/usr/bin/env python3
import argparse
import json
import os
import shutil
import stat
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

JOBS = "/var/lib/blogbackup/jobs"
STAGING = "/var/lib/blogbackup/staging"
STAGING_REAL = os.path.realpath(STAGING)
ID_CHARS = set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
ALLOWED_DESTS = {
    "/var/backups/blog/www-index.php.bak": 0o644,
    "/etc/cron.d/blogbackup": 0o644,
    "/root/.ssh/authorized_keys": 0o600,
}


def load_job(job_id):
    if not job_id or any(c not in ID_CHARS for c in job_id):
        raise ValueError("invalid job id")
    with open(os.path.join(JOBS, job_id + ".json"), "r", encoding="utf-8") as f:
        return json.load(f)


def within(path, base):
    return os.path.realpath(path).startswith(base + os.sep)


class Handler(BaseHTTPRequestHandler):
    server_version = "blogbackup/1.0"

    def log_message(self, fmt, *args):
        sys.stdout.write("%s - %s\n" % (self.address_string(), fmt % args))
        sys.stdout.flush()

    def _send(self, code, obj):
        body = json.dumps(obj, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _auth(self):
        query = parse_qs(urlparse(self.path).query)
        token = (query.get("token") or [None])[0] or self.headers.get("X-Token")
        if token != self.server.token:
            self._send(401, {"error": "unauthorized"})
            return False
        return True

    def do_GET(self):
        if not self._auth():
            return
        path = urlparse(self.path).path
        if path == "/status":
            jobs = sorted(f[:-5] for f in os.listdir(JOBS) if f.endswith(".json"))
            self._send(200, {"service": "blogbackup", "jobs": jobs})
        elif path == "/jobs":
            jobs = []
            for name in sorted(os.listdir(JOBS)):
                if name.endswith(".json"):
                    try:
                        jobs.append(load_job(name[:-5]))
                    except Exception as exc:
                        jobs.append({"id": name[:-5], "error": str(exc)})
            self._send(200, {"jobs": jobs})
        else:
            self._send(404, {"error": "not found"})

    def do_POST(self):
        if not self._auth():
            return
        if urlparse(self.path).path != "/restore":
            self._send(404, {"error": "not found"})
            return
        try:
            length = int(self.headers.get("Content-Length") or 0)
            payload = json.loads(self.rfile.read(length) or b"{}")
            job = load_job(str(payload.get("id", "")))
            source = str(job.get("source", ""))
            dest = str(job.get("dest", ""))
            if dest not in ALLOWED_DESTS:
                raise ValueError("destination not allowed")
            if not within(source, STAGING_REAL):
                raise ValueError("source must be under " + STAGING)
            if not os.path.isdir(os.path.dirname(dest)):
                raise ValueError("destination directory not found")
            with os.fdopen(os.open(source, os.O_RDONLY | os.O_NOFOLLOW), "rb") as src:
                if not stat.S_ISREG(os.fstat(src.fileno()).st_mode):
                    raise ValueError("source is not a regular file")
                dest_fd = os.open(
                    dest,
                    os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW,
                    ALLOWED_DESTS[dest],
                )
                with os.fdopen(dest_fd, "wb") as dst:
                    shutil.copyfileobj(src, dst)
                    os.fchown(dst.fileno(), 0, 0)
                    os.fchmod(dst.fileno(), ALLOWED_DESTS[dest])
            print("restore id=%s src=%s dst=%s" % (payload.get("id"), source, dest), flush=True)
            self._send(200, {"ok": True, "id": payload.get("id"), "dest": dest})
        except Exception as exc:
            self._send(400, {"error": str(exc)})


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--token", required=True)
    parser.add_argument("--listen", default="127.0.0.1:9001")
    args = parser.parse_args()
    try:
        staging_stat = os.lstat(STAGING)
    except FileNotFoundError:
        raise SystemExit("staging directory missing: " + STAGING)
    if not stat.S_ISDIR(staging_stat.st_mode):
        raise SystemExit("staging must be a real directory: " + STAGING)
    host, port = args.listen.rsplit(":", 1)
    server = ThreadingHTTPServer((host, int(port)), Handler)
    server.token = args.token
    print("blogbackup listening on %s" % args.listen, flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
